import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DosMas',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: WebViewContainer(),
    );
  }
}

// Clase para gestionar logs
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  final List<LogEntry> _logs = [];
  final int maxLogs = 100; // Número máximo de logs a mantener
  List<Function(List<LogEntry>)> _listeners = [];

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void addListener(Function(List<LogEntry>) listener) {
    _listeners.add(listener);
  }

  void removeListener(Function(List<LogEntry>) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (var listener in _listeners) {
      listener(_logs);
    }
  }

  void log(String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(
      message: message,
      level: level,
      timestamp: DateTime.now(),
    );

    _logs.add(entry);

    // Limitar el número de logs
    if (_logs.length > maxLogs) {
      _logs.removeAt(0);
    }

    _notifyListeners();
  }

  void debug(String message) => log(message, level: LogLevel.debug);
  void info(String message) => log(message, level: LogLevel.info);
  void warning(String message) => log(message, level: LogLevel.warning);
  void error(String message) => log(message, level: LogLevel.error);

  void clear() {
    _logs.clear();
    _notifyListeners();
  }
}

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.level,
    required this.timestamp,
  });

  Color get color {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  String get levelName {
    switch (level) {
      case LogLevel.debug:
        return "DEBUG";
      case LogLevel.info:
        return "INFO";
      case LogLevel.warning:
        return "WARN";
      case LogLevel.error:
        return "ERROR";
    }
  }
}


class WebViewContainer extends StatefulWidget {
  @override
  createState() => _WebViewContainerState();
}

class _WebViewContainerState extends State<WebViewContainer> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _isButtonHandlerActive = false;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Se elimina la llamada a _checkLocationPermission() al inicio
    // _checkLocationPermission();  <-- Esta línea debe eliminarse
  }


  Future<void> _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    // Ya no necesitamos comprobar permisos de ubicación en segundo plano
  }

  Future<void> _setupDirectFileInputHandlers() async {
    String script = '''
  (function() {
    // Lista de IDs de inputs para manejar
    const targetInputs = [
      'pago_moviles_peru_trf_image', 
      'file',
      // Añadir otros IDs conocidos aquí
    ];
    
    // Función para encontrar y modificar inputs
    function setupInputHandlers() {
      console.log("Configurando manejadores directos para inputs de archivo");
      
      // 1. Encontrar todos los inputs de tipo file
      const fileInputs = document.querySelectorAll('input[type="file"]');
      
      fileInputs.forEach(function(input) {
        // Evitar configurar el mismo input dos veces
        if (input.hasCustomHandler) return;
        
        const inputId = input.id || 'unknown_' + Math.random().toString(36).substr(2, 9);
        console.log("Configurando input: " + inputId);
        
        // Guardar el manejador original si existe
        const originalOnChange = input.onchange;
        
        // Ocultar el input original
        const originalDisplay = input.style.display;
        const originalVisibility = input.style.visibility;
        
        // Crear un botón personalizado junto al input
        const customButton = document.createElement('button');
        customButton.type = 'button';
        customButton.className = 'custom-file-button';
        customButton.textContent = 'Seleccionar archivo';
        customButton.style.marginLeft = '10px';
        customButton.style.padding = '5px 10px';
        customButton.style.background = '#4285f4';
        customButton.style.color = 'white';
        customButton.style.border = 'none';
        customButton.style.borderRadius = '4px';
        customButton.style.cursor = 'pointer';
        
        // Añadir el botón después del input
        if (input.parentNode) {
          input.parentNode.insertBefore(customButton, input.nextSibling);
          
          // Añadir un span para mostrar el nombre del archivo
          const fileNameDisplay = document.createElement('span');
          fileNameDisplay.className = 'file-name-display';
          fileNameDisplay.style.marginLeft = '10px';
          fileNameDisplay.style.color = '#666';
          input.parentNode.insertBefore(fileNameDisplay, customButton.nextSibling);
          
          // Guardar referencia al span
          input.fileNameDisplay = fileNameDisplay;
          
          // Evento de clic en el botón personalizado
          customButton.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            
            console.log("Botón personalizado clickeado para input: " + inputId);
            window.FileUploadHandler.postMessage('selectFile:' + inputId);
            
            return false;
          });
          
          input.hasCustomHandler = true;
        }
      });
    }
    
    // Configurar inputs existentes
    setupInputHandlers();
    
    // Observar cambios en el DOM
    const observer = new MutationObserver(function(mutations) {
      let shouldSetup = false;
      
      mutations.forEach(function(mutation) {
        if (mutation.addedNodes.length > 0) {
          shouldSetup = true;
        }
      });
      
      if (shouldSetup) {
        setupInputHandlers();
      }
    });
    
    observer.observe(document.body, {
      childList: true,
      subtree: true
    });
    
    console.log("Configuración de manejadores directos completada");
  })();
  ''';

    try {
      await _controller?.runJavascript(script);
    } catch (e) {
    }
  }

  Future<void> _handleFileUpload(String inputId) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile != null) {

        // Leer el archivo como bytes
        final bytes = await pickedFile.readAsBytes();

        // Convertir a base64
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

        // Nombre del archivo y tipo
        final fileName = pickedFile.name;
        final fileType = 'image/jpeg';

        // Enfoque simplificado
        await _directlyInjectFile(inputId, base64Image, fileName, fileType);

      } else {
      }
    } catch (e) {
    }
  }
  Future<void> _directlyInjectFile(String inputId, String base64Image, String fileName, String fileType) async {
    String script = '''
  (function() {
    try {
      console.log("Inyectando archivo directamente para: " + "$inputId");
      
      // Encontrar el input
      let input = document.getElementById("$inputId");
      
      // Si no se encuentra por ID, intentar con otros selectores
      if (!input) {
        if ("$inputId".startsWith("unknown")) {
          input = document.querySelector('input[type="file"]');
        }
      }
      
      if (!input) {
        console.error("No se pudo encontrar el input de archivo");
        return;
      }
      
      // Convertir base64 a Blob
      const base64Response = '$base64Image';
      const byteCharacters = atob(base64Response.split(',')[1]);
      const byteArrays = [];
      
      for (let i = 0; i < byteCharacters.length; i++) {
        byteArrays.push(byteCharacters.charCodeAt(i));
      }
      
      const byteArray = new Uint8Array(byteArrays);
      const blob = new Blob([byteArray], {type: '$fileType'});
      
      // Crear un objeto File
      const file = new File([blob], '$fileName', {type: '$fileType'});
      
      // Aplicar el archivo al input
      const dataTransfer = new DataTransfer();
      dataTransfer.items.add(file);
      input.files = dataTransfer.files;
      
      // Actualizar el visualizador de nombre de archivo si existe
      if (input.fileNameDisplay) {
        input.fileNameDisplay.textContent = file.name;
      }
      
      // Disparar eventos
      console.log("Disparando eventos para input: " + input.id);
      
      // 1. Evento change
      const changeEvent = new Event('change', { bubbles: true });
      input.dispatchEvent(changeEvent);
      
      // 2. Evento input
      const inputEvent = new Event('input', { bubbles: true });
      input.dispatchEvent(inputEvent);
      
      // 3. Si tiene un atributo onchange, ejecutarlo manualmente
      if (input.hasAttribute('onchange')) {
        const onchangeAttr = input.getAttribute('onchange');
        console.log("Ejecutando onchange: " + onchangeAttr);
        
        try {
          // Ejecutar el código onchange reemplazando 'this' con 'input'
          const evalCode = onchangeAttr.replace(/this/g, 'input');
          eval(evalCode);
        } catch (evalError) {
          console.error("Error ejecutando onchange: " + evalError);
          
          // Intento alternativo - buscar la función por nombre
          if (onchangeAttr.includes('prepareImage')) {
            console.log("Intentando ejecutar prepareImage directamente");
            
            try {
              if (typeof window.prepareImage === 'function') {
                window.prepareImage(input);
                console.log("prepareImage ejecutado con éxito");
              } else {
                console.error("La función prepareImage no está definida globalmente");
              }
            } catch (fnError) {
              console.error("Error ejecutando prepareImage: " + fnError);
            }
          }
        }
      }
      
      console.log("Archivo inyectado exitosamente");
      
      // Crear un indicador visual de éxito
      const successMessage = document.createElement('div');
      successMessage.textContent = "✓ Archivo subido: " + '$fileName';
      successMessage.style.color = 'green';
      successMessage.style.padding = '5px';
      successMessage.style.marginTop = '5px';
      successMessage.style.fontWeight = 'bold';
      
      if (input.parentNode) {
        input.parentNode.appendChild(successMessage);
        
        // Eliminar el mensaje después de unos segundos
        setTimeout(function() {
          if (successMessage.parentNode) {
            successMessage.parentNode.removeChild(successMessage);
          }
        }, 5000);
      }
      
    } catch (error) {
      console.error("Error en _directlyInjectFile: " + error);
    }
  })();
  ''';

    await _controller?.runJavascript(script);
  }
  // 1. Modifica el método _setupFileUploadHandler para usar el selector correcto
  Future<void> _setupFileUploadHandler() async {
    String script = '''
  (function() {
    // NO interceptaremos clics en elementos de tipo file
    // En lugar de eso, detectaremos botones cercanos

    document.addEventListener('click', function(e) {
      var target = e.target;
      
      // IMPORTANTE: Si es un input file, NO interceptar
      if (target.tagName === 'INPUT' && target.type === 'file') {
        console.log("Click directo en input file, NO interceptando");
        return true; // Permitir comportamiento nativo
      }
      
      // Verificar si es el botón con clase box__button
      let isUploadButton = false;
      let currentElement = target;
      let depth = 0;
      const maxDepth = 5;
      
      while (currentElement && depth < maxDepth) {
        if (currentElement.tagName === 'BUTTON' && 
            (currentElement.classList.contains('box__button') || currentElement.classList.contains('boxbutton'))) {
          isUploadButton = true;
          break;
        }
        currentElement = currentElement.parentElement;
        depth++;
      }
      
      // Si es un botón de carga, usarlo para buscar su input relacionado
      if (isUploadButton) {
        console.log("Botón de carga detectado: " + currentElement.className);
        
        // Buscar el input relacionado
        const form = currentElement.closest('form');
        if (form) {
          const fileInput = form.querySelector('input[type="file"]');
          if (fileInput) {
            console.log("Input file asociado encontrado: " + fileInput.id);
            // En lugar de prevenir, modificamos el evento
            e.preventDefault();
            e.stopPropagation();
            window.FileUploadHandler.postMessage('selectFile:' + (fileInput.id || 'unknown'));
            return false;
          }
        }
      }
      
      // NUNCA interceptar clics en inputs o labels asociados a files
      // Permitir que el comportamiento nativo funcione
    }, true);
    
    // Añadir listeners específicos para los inputs de archivo
    function setupFileInputs() {
      // Agregar listeners específicos a los inputs
      const fileInputs = document.querySelectorAll('input[type="file"]');
      fileInputs.forEach(function(input) {
        if (!input.hasNativeHandler) {
          input.hasNativeHandler = true;
          console.log("Estableciendo listener nativo para input file: " + input.id);
          
          // Escuchar el evento change nativo
          input.addEventListener('change', function(e) {
            // Si el usuario seleccionó un archivo a través del selector nativo,
            // no necesitamos hacer nada más, el navegador lo maneja
            if (input.files && input.files.length > 0) {
              console.log("Archivo seleccionado nativamente: " + input.files[0].name);
              
              // Si hay una función prepareImage, se ejecutará normalmente
              // ya que estamos permitiendo el evento change nativo
            }
          });
        }
      });
    }
    
    // Configurar los inputs existentes
    setupFileInputs();
    
    // Observar cambios en el DOM para detectar nuevos inputs
    const observer = new MutationObserver(function(mutations) {
      mutations.forEach(function(mutation) {
        if (mutation.addedNodes.length) {
          mutation.addedNodes.forEach(function(node) {
            if (node.nodeType === 1) { // ELEMENT_NODE
              setupFileInputs();
            }
          });
        }
      });
    });
    
    observer.observe(document.body, { 
      childList: true, 
      subtree: true 
    });
    
    console.log("Handler de carga de archivos configurado (versión mejorada)");
  })();
  ''';

    try {
      await _controller?.runJavascript(script);
    } catch (e) {
    }
  }


// 2. Modifica el método _injectFileToFormJS para encontrar el input correcto
  Future<void> _injectFileToFormJS(String base64Image, String fileName, String fileType, String inputId) async {
    String script = '''
  (function() {
    try {
      console.log("Inyectando archivo en formulario para input: $inputId");
      
      // Convertir base64 a Blob
      const base64Response = '$base64Image';
      const byteCharacters = atob(base64Response.split(',')[1]);
      const byteArrays = [];
      
      for (let i = 0; i < byteCharacters.length; i++) {
        byteArrays.push(byteCharacters.charCodeAt(i));
      }
      
      const byteArray = new Uint8Array(byteArrays);
      const blob = new Blob([byteArray], {type: '$fileType'});
      
      // Crear un objeto File
      const file = new File([blob], '$fileName', {type: '$fileType'});
      
      // Búsqueda de input específica según el ID recibido
      let fileInput = null;
      
      if (inputId === 'pago_moviles_peru_trf_image') {
        fileInput = document.getElementById('pago_moviles_peru_trf_image');
      } else if (inputId === 'unknown') {
        // Buscar cualquier input de tipo file en la página
        fileInput = document.querySelector('input.box__file') || 
                   document.getElementById('file') ||
                   document.querySelector('input[type="file"]');
      } else {
        // Buscar por ID específico o alternativas
        fileInput = document.getElementById(inputId) || 
                   document.querySelector('input.box__file') || 
                   document.getElementById('file');
      }
      
      if (fileInput) {
        console.log("Input file encontrado: " + fileInput.id);
        
        // Crear una DataTransfer y agregar el archivo
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(file);
        fileInput.files = dataTransfer.files;
        
        // Disparar evento change
        const event = new Event('change', { bubbles: true });
        fileInput.dispatchEvent(event);
        
        // Si tiene un manejador onchange específico, intentar ejecutarlo
        if (fileInput.hasAttribute('onchange')) {
          const onchangeAttr = fileInput.getAttribute('onchange');
          if (onchangeAttr && onchangeAttr.includes('prepareImage')) {
            console.log("Ejecutando función prepareImage");
            try {
              // Si la función es prepareImage(this), ejecutarla con el input como argumento
              if (typeof window.prepareImage === 'function') {
                window.prepareImage(fileInput);
              }
            } catch (err) {
              console.error("Error ejecutando prepareImage: " + err);
            }
          }
        }
        
        console.log("Archivo inyectado exitosamente");
      } else {
        console.error("No se encontró un input file");
      }
    } catch (e) {
      console.error("Error al inyectar archivo: " + e);
    }
  })();
  ''';

    await _controller?.runJavascript(script);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          WebView(
            initialUrl: 'https://dosmas-pe.com/',
            javascriptMode: JavascriptMode.unrestricted,
            onWebViewCreated: (WebViewController webViewController) {
              _controller = webViewController;
            },
            onPageStarted: (String url) {
              setState(() {
                _isLoading = true;
              });
            },
            onPageFinished: (String url) async {
              setState(() {
                _isLoading = false;
              });

              // Configurar redirección de consola primero para depuración
              await _setupConsoleRedirection();

              // Verificar si estamos en la página de checkout de WooCommerce
              bool isCheckout = url.contains('/checkout') || url.contains('/finalizar-compra');

              if (!_isButtonHandlerActive || isCheckout) {
                // Configurar handlers específicos para WooCommerce
                if (isCheckout) {
                  await _setupSpecificButtonHandler();
                }

                // Configurar handlers generales como respaldo
                await _setupButtonInteractions();
                await _setupGlobalClickHandler();

                _isButtonHandlerActive = true;
              }
              await _setupDirectFileInputHandlers();

              // Inyectar código para depuración y verificación
              await _controller?.runJavascript('''
                console.log("Página cargada completamente: $url");
                
                // Verificar si estamos en checkout
                var isCheckoutPage = document.body.classList.contains('woocommerce-checkout') || 
                                      document.querySelector('.woocommerce-checkout') !== null ||
                                      window.location.href.includes('/checkout') ||
                                      window.location.href.includes('/finalizar-compra');
                
                console.log("Verificación JavaScript - ¿Es checkout?: " + isCheckoutPage);
                
                // Verificar elementos específicos
                setTimeout(function() {
                  var initialButton = document.getElementById('initialbutton');
                  console.log("Botón initialbutton: " + (initialButton ? "Encontrado" : "No encontrado"));
                  
                  var deliveryField = document.getElementById('delivery_address');
                  console.log("Campo delivery_address: " + (deliveryField ? "Encontrado" : "No encontrado"));
                  
                  var locationDisplay = document.getElementById('locationDisplay');
                  console.log("Div locationDisplay: " + (locationDisplay ? "Encontrado" : "No encontrado"));
                  
                  // Si estamos en checkout pero no encontramos elementos, podría estar cargando aún
                  if (isCheckoutPage && (!initialButton || !deliveryField)) {
                    console.log("Elementos de checkout no encontrados aún, programando verificación adicional");
                    setTimeout(function() {
                      var initialButton = document.getElementById('initialbutton');
                      console.log("Verificación retrasada - Botón initialbutton: " + 
                                  (initialButton ? "Encontrado" : "No encontrado"));
                    }, 3000);
                  }
                }, 1000);
              ''');
            },
            onWebResourceError: (WebResourceError error) {
              if (error.description.isNotEmpty) {
                _launchURL(error.description);
              }
            },
            javascriptChannels: {
              JavascriptChannel(
                name: 'LocationHandler',
                onMessageReceived: (JavascriptMessage message) async {
                  try {
                    // Usar el manejador específico para WooCommerce
                    await _handleWooCommerceLocation();
                  } catch (e) {
                    // Intento de respaldo con el manejador genérico
                    try {
                      await _handleLocationRequest();
                    } catch (e2) {
                    }
                  }
                },
              ),
              JavascriptChannel(
                name: 'FileUploadHandler',
                onMessageReceived: (JavascriptMessage message) async {
                  String msg = message.message;
                  String inputId = 'unknown';

                  if (msg.contains(':')) {
                    final parts = msg.split(':');
                    if (parts.length > 1) {
                      inputId = parts[1];
                    }
                  }

                  await _handleFileUpload(inputId);
                },
              ),

              JavascriptChannel(
                name: 'ConsoleLogger',
                onMessageReceived: (JavascriptMessage message) {
                },
              ),
              JavascriptChannel(
                name: 'DebugChannel',
                onMessageReceived: (JavascriptMessage message) {
                  String logMessage = message.message;
                  if (logMessage.startsWith("ERROR:")) {
                  } else if (logMessage.startsWith("WARN:")) {
                  } else {
                  }
                },
              ),
            },
          ),
          _isLoading
              ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF1F50)),
              ))
              : SizedBox.shrink(),

          // Posicionamos el widget de logs en la parte inferior

        ],
      ),
    );
  }

  Future<void> _setupConsoleRedirection() async {
    try {
      await _controller?.runJavascript('''
        (function() {
          // Guardar las funciones originales de console
          var originalLog = console.log;
          var originalError = console.error;
          var originalWarn = console.warn;
          
          // Reemplazar console.log
          console.log = function() {
            // Llamar a la función original
            originalLog.apply(console, arguments);
            
            // Convertir los argumentos a una cadena
            var args = Array.prototype.slice.call(arguments);
            var message = args.map(function(arg) {
              return typeof arg === 'object' ? JSON.stringify(arg) : String(arg);
            }).join(' ');
            
            // Enviar al canal de JavaScript
            window.ConsoleLogger.postMessage('[LOG] ' + message);
          };
          
          // Reemplazar console.error
          console.error = function() {
            originalError.apply(console, arguments);
            var args = Array.prototype.slice.call(arguments);
            var message = args.map(function(arg) {
              return typeof arg === 'object' ? JSON.stringify(arg) : String(arg);
            }).join(' ');
            window.ConsoleLogger.postMessage('[ERROR] ' + message);
          };
          
          // Reemplazar console.warn
          console.warn = function() {
            originalWarn.apply(console, arguments);
            var args = Array.prototype.slice.call(arguments);
            var message = args.map(function(arg) {
              return typeof arg === 'object' ? JSON.stringify(arg) : String(arg);
            }).join(' ');
            window.ConsoleLogger.postMessage('[WARN] ' + message);
          };
          
          // Indicar que la redirección se ha configurado
          window.ConsoleLogger.postMessage('Redirección de consola configurada');
        })();
      ''');
    } catch (e) {
    }
  }

  Future<void> _setupSpecificButtonHandler() async {
    try {
      await _controller?.runJavascript('''
        (function() {
          // Selección directa del elemento tal como está en WooCommerce
          function setupWooCommerceButton() {
            console.log("Buscando botón WooCommerce con ID 'initialbutton'");
            var button = document.querySelector('a[id="initialbutton"]');
            
            if (!button) {
              console.log("Intentando con selector alternativo");
              button = document.getElementById('initialbutton');
            }
            
            if (!button) {
              console.log("Intentando encontrar cualquier elemento con texto 'Obtener ubicación'");
              var elements = document.querySelectorAll('a, button');
              for (var i = 0; i < elements.length; i++) {
                if (elements[i].textContent && elements[i].textContent.trim() === 'Obtener ubicación') {
                  button = elements[i];
                  console.log("Encontrado botón por texto: ", button);
                  break;
                }
              }
            }
            
            if (button) {
              console.log("Botón WooCommerce encontrado:", button);
              
              // Verificar si ya tiene un listener
              if (!button.hasLocationListener) {
                button.hasLocationListener = true;
                
                button.addEventListener('click', function(e) {
                  console.log("¡Clic en botón WooCommerce detectado!");
                  e.preventDefault();
                  e.stopPropagation();
                  
                  // Mostrar indicador visual para confirmar que el botón fue presionado
                  var originalColor = button.style.backgroundColor;
                  button.style.backgroundColor = '#FF5733'; // Cambiar color temporalmente
                  setTimeout(function() {
                    button.style.backgroundColor = originalColor;
                  }, 500);
                  
                  // Enviar mensaje al canal de JavaScript
                  console.log("Enviando mensaje a LocationHandler");
                  window.LocationHandler.postMessage('getLocation');
                  
                  return false;
                }, true);
                
                console.log("Listener añadido al botón WooCommerce");
                return true;
              } else {
                console.log("El botón ya tiene un listener asignado");
                return true;
              }
            }
            
            console.log("Botón WooCommerce no encontrado en esta búsqueda");
            return false;
          }
          
          // Intentar configurar inmediatamente
          var configured = setupWooCommerceButton();
          
          // Si no se encuentra, intentar nuevamente después de un retraso
          if (!configured) {
            console.log("Programando búsqueda retrasada del botón");
            for (let delay of [500, 1000, 2000, 3000, 5000]) {
              setTimeout(function() {
                if (!configured) {
                  configured = setupWooCommerceButton();
                }
              }, delay);
            }
          }
          
          // También observar cambios en el DOM para detectar cuando se agrega el botón
          var observer = new MutationObserver(function(mutations) {
            if (!configured) {
              configured = setupWooCommerceButton();
              if (configured) {
                console.log("Botón configurado después de cambio en DOM");
              }
            }
          });
          
          observer.observe(document.body, { 
            childList: true, 
            subtree: true,
            attributes: true,
            attributeFilter: ['id', 'class']
          });
          
          console.log("Observer configurado para detectar cambios en DOM");
        })();
      ''');

    } catch (e) {
    }
  }

  Future<void> _setupButtonInteractions() async {
    try {
      // Script con un enfoque más directo
      await _controller?.runJavascript('''
        (function() {
          try {
            // Función específica para el botón initialbutton
            function setupInitialButton() {
              var initialButton = document.getElementById('initialbutton');
              if (initialButton) {
                console.log("Botón initialbutton encontrado, configurando evento");
                initialButton.addEventListener('click', function(e) {
                  console.log("Botón initialbutton clickeado");
                  // Importante: preventDefault para evitar comportamiento predeterminado
                  e.preventDefault();
                  // Enviar mensaje al canal de JavaScript
                  window.LocationHandler.postMessage('getLocation');
                  return false;
                }, true); // Usar captura para interceptar antes
                return true;
              }
              return false;
            }
            
            // Intentar configurar el botón inmediatamente
            let configured = setupInitialButton();
            
            // Si no se encuentra, intentar después de un pequeño retraso
            if (!configured) {
              setTimeout(function() {
                setupInitialButton();
              }, 1000);
            }
            
            // También observamos el DOM para detectar cuando aparezca el botón
            const observer = new MutationObserver(function(mutations) {
              // Si aún no está configurado, intentar configurarlo
              if (!configured) {
                configured = setupInitialButton();
                if (configured) {
                  // Si se configuró exitosamente, dejar de observar
                  observer.disconnect();
                }
              }
            });
            
            observer.observe(document.body, { childList: true, subtree: true });
          } catch (e) {
            console.error("Error configurando botón initialbutton: " + e);
          }
        })();
      ''');

      // Verificar si se ha configurado correctamente
      final String result = await _controller?.runJavascriptReturningResult('''
        (function() {
          var btn = document.getElementById('initialbutton');
          return btn ? "Botón encontrado" : "Botón no encontrado";
        })();
      ''') ?? "Error al verificar";


    } catch (e) {
    }
  }

  Future<void> _setupGlobalClickHandler() async {
    try {
      await _controller?.runJavascript('''
        (function() {
          // Función que verifica si un elemento es o contiene el botón que buscamos
          function isTargetButton(element) {
            // Verificar por ID
            if (element.id === 'initialbutton') return true;
            
            // Verificar por otras propiedades que puedan identificar el botón
            if (element.classList && element.classList.contains('location-button')) return true;
            
            // Verificar si es un botón con ciertos atributos o contenido
            if (element.tagName === 'BUTTON' || element.tagName === 'A') {
              // Verificar texto interno
              if (element.innerText && element.innerText.toLowerCase().includes('ubicación')) return true;
              
              // Verificar si contiene un ícono específico
              if (element.querySelector('i.fa-map-marker') || element.querySelector('i.fa-location')) return true;
            }
            
            return false;
          }
          
          // Agregar listener de clic a todo el documento
          document.addEventListener('click', function(e) {
            // Verificar el elemento clickeado y sus padres
            let currentElement = e.target;
            let depth = 0;
            const maxDepth = 5; // Limitar la profundidad para evitar problemas
            
            while (currentElement && depth < maxDepth) {
              if (isTargetButton(currentElement)) {
                console.log("Botón objetivo detectado y clickeado");
                // Evitar comportamiento predeterminado
                e.preventDefault();
                e.stopPropagation();
                
                // Notificar a través del canal de JavaScript
                window.LocationHandler.postMessage('getLocation');
                
                return false;
              }
              
              // Subir en la jerarquía DOM
              currentElement = currentElement.parentElement;
              depth++;
            }
          }, true); // Usar fase de captura para interceptar antes
          
          console.log("Handler global de clics configurado");
        })();
      ''');

    } catch (e) {
    }
  }

  Future<void> _handleWooCommerceLocation() async {
    final position = await _fetchUserLocation();
    if (position != null) {
      // Coordenadas para mostrar y almacenar
      final locationString = "https://maps.google.com/maps?q=${position.latitude},${position.longitude}";

      try {
        // Script específico para WooCommerce que actualiza el campo de dirección
        await _controller?.runJavascript('''
        (function() {
          console.log("Actualizando campos de WooCommerce con ubicación");
          
          // Actualizar el campo de dirección
          var deliveryField = document.getElementById('delivery_address');
          if (deliveryField) {
            deliveryField.value = '$locationString';
            console.log("Campo delivery_address actualizado");
            
            // Disparar eventos para asegurar que WooCommerce detecte el cambio
            var changeEvent = new Event('change', { bubbles: true });
            deliveryField.dispatchEvent(changeEvent);
            
            var inputEvent = new Event('input', { bubbles: true });
            deliveryField.dispatchEvent(inputEvent);
          } else {
            console.log("Campo delivery_address no encontrado");
          }
          
          // Actualizar el div de visualización si existe, pero sin el enlace
          var locationDisplay = document.getElementById('locationDisplay');
          if (locationDisplay) {
            locationDisplay.innerHTML = '<p>Ubicación obtenida</p>';
            locationDisplay.style.color = '#2335c2';
            locationDisplay.style.fontWeight = 'bold';
            console.log("Display de ubicación actualizado (sin enlace a Google Maps)");
          }
          
          // Alternativamente, buscar por selector de WooCommerce
          if (!deliveryField) {
            var wooField = document.querySelector('input[name="delivery_address"]');
            if (wooField) {
              wooField.value = '$locationString';
              console.log("Campo WooCommerce actualizado por selector alternativo");
              
              var changeEvent = new Event('change', { bubbles: true });
              wooField.dispatchEvent(changeEvent);
            }
          }
          
          console.log("Actualización de ubicación completada");
          
          // Notificar que el proceso se ha completado (opcional)
          var initialButton = document.getElementById('initialbutton');
          if (initialButton) {
            initialButton.innerHTML = "✓ Ubicación obtenida";
            initialButton.style.backgroundColor = "#4CAF50";
            setTimeout(function() {
              initialButton.innerHTML = "Obtener ubicación";
              initialButton.style.backgroundColor = "#2335c2";
            }, 3000);
          }
        })();
      ''');
      } catch (e) {
      }
    } else {
    }
  }

  Future<void> _handleLocationRequest() async {
    final position = await _fetchUserLocation();
    if (position != null) {
      // Crear una dirección formateada con la ubicación
      final locationString = "https://maps.google.com/maps?q=${position.latitude},${position.longitude}";

      // Intentar diferentes selectores para asegurar que funcione
      try {
        await _controller?.runJavascript('''
        (function() {
          // Intentar con ID delivery_address
          var input = document.getElementById('delivery_address');
          if (input) {
            input.value = '$locationString';
            return;
          }
          
          // Intentar con atributo name="delivery_address"
          input = document.querySelector('input[name="delivery_address"]');
          if (input) {
            input.value = '$locationString';
            return;
          }
          
          // Intentar con cualquier campo de entrada que tenga "address" en su id
          input = document.querySelector('input[id*="address"]');
          if (input) {
            input.value = '$locationString';
            return;
          }
          
          // Intentar encontrar cualquier campo de entrada visible
          var inputs = document.querySelectorAll('input[type="text"]:not([style*="display: none"])');
          if (inputs.length > 0) {
            inputs[0].value = '$locationString';
          }
        })();
      ''');
      } catch (e) {
      }
    }
  }


  Future<Position?> _fetchUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Mostrar diálogo para habilitar ubicación
        _showLocationServiceDialog();
        return null;
      }

      // Verificación de permisos solo para ubicación en primer plano
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // El usuario ha denegado permanentemente los permisos
        _showPermissionDeniedDialog();
        return null;
      }

      // Obtener ubicación solo en primer plano
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, // Cambiado de best a high para reducir uso de batería
        timeLimit: const Duration(seconds: 15),
      );
      return position;
    } catch (e) {
      return null;
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Ubicación desactivada'),
          content: Text('Por favor activa los servicios de ubicación en tu dispositivo para continuar.'),
          actions: [
            TextButton(
              child: Text('Configuración'),
              onPressed: () {
                Geolocator.openLocationSettings();
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Permiso denegado'),
          content: Text('Has denegado el permiso de ubicación permanentemente. Por favor, habilítalo en la configuración de la aplicación para usar esta función.'),
          actions: [
            TextButton(
              child: Text('Configuración'),
              onPressed: () {
                Geolocator.openAppSettings();
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }
}