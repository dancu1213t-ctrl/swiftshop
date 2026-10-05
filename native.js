(function () {
    'use strict';

    /*! Capacitor: https://capacitorjs.com/ - MIT License */
    var ExceptionCode;
    (function (ExceptionCode) {
        /**
         * API is not implemented.
         *
         * This usually means the API can't be used because it is not implemented for
         * the current platform.
         */
        ExceptionCode["Unimplemented"] = "UNIMPLEMENTED";
        /**
         * API is not available.
         *
         * This means the API can't be used right now because:
         *   - it is currently missing a prerequisite, such as network connectivity
         *   - it requires a particular platform or browser version
         */
        ExceptionCode["Unavailable"] = "UNAVAILABLE";
    })(ExceptionCode || (ExceptionCode = {}));
    class CapacitorException extends Error {
        constructor(message, code, data) {
            super(message);
            this.message = message;
            this.code = code;
            this.data = data;
        }
    }
    const getPlatformId = (win) => {
        var _a, _b;
        if (win === null || win === void 0 ? void 0 : win.androidBridge) {
            return 'android';
        }
        else if ((_b = (_a = win === null || win === void 0 ? void 0 : win.webkit) === null || _a === void 0 ? void 0 : _a.messageHandlers) === null || _b === void 0 ? void 0 : _b.bridge) {
            return 'ios';
        }
        else {
            return 'web';
        }
    };

    const createCapacitor = (win) => {
        const capCustomPlatform = win.CapacitorCustomPlatform || null;
        const cap = win.Capacitor || {};
        const Plugins = (cap.Plugins = cap.Plugins || {});
        const getPlatform = () => {
            return capCustomPlatform !== null ? capCustomPlatform.name : getPlatformId(win);
        };
        const isNativePlatform = () => getPlatform() !== 'web';
        const isPluginAvailable = (pluginName) => {
            const plugin = registeredPlugins.get(pluginName);
            if (plugin === null || plugin === void 0 ? void 0 : plugin.platforms.has(getPlatform())) {
                // JS implementation available for the current platform.
                return true;
            }
            if (getPluginHeader(pluginName)) {
                // Native implementation available.
                return true;
            }
            return false;
        };
        const getPluginHeader = (pluginName) => { var _a; return (_a = cap.PluginHeaders) === null || _a === void 0 ? void 0 : _a.find((h) => h.name === pluginName); };
        const handleError = (err) => win.console.error(err);
        const registeredPlugins = new Map();
        const registerPlugin = (pluginName, jsImplementations = {}) => {
            const registeredPlugin = registeredPlugins.get(pluginName);
            if (registeredPlugin) {
                console.warn(`Capacitor plugin "${pluginName}" already registered. Cannot register plugins twice.`);
                return registeredPlugin.proxy;
            }
            const platform = getPlatform();
            const pluginHeader = getPluginHeader(pluginName);
            let jsImplementation;
            const loadPluginImplementation = async () => {
                if (!jsImplementation && platform in jsImplementations) {
                    jsImplementation =
                        typeof jsImplementations[platform] === 'function'
                            ? (jsImplementation = await jsImplementations[platform]())
                            : (jsImplementation = jsImplementations[platform]);
                }
                else if (capCustomPlatform !== null && !jsImplementation && 'web' in jsImplementations) {
                    jsImplementation =
                        typeof jsImplementations['web'] === 'function'
                            ? (jsImplementation = await jsImplementations['web']())
                            : (jsImplementation = jsImplementations['web']);
                }
                return jsImplementation;
            };
            const createPluginMethod = (impl, prop) => {
                var _a, _b;
                if (pluginHeader) {
                    const methodHeader = pluginHeader === null || pluginHeader === void 0 ? void 0 : pluginHeader.methods.find((m) => prop === m.name);
                    if (methodHeader) {
                        if (methodHeader.rtype === 'promise') {
                            return (options) => cap.nativePromise(pluginName, prop.toString(), options);
                        }
                        else {
                            return (options, callback) => cap.nativeCallback(pluginName, prop.toString(), options, callback);
                        }
                    }
                    else if (impl) {
                        return (_a = impl[prop]) === null || _a === void 0 ? void 0 : _a.bind(impl);
                    }
                }
                else if (impl) {
                    return (_b = impl[prop]) === null || _b === void 0 ? void 0 : _b.bind(impl);
                }
                else {
                    throw new CapacitorException(`"${pluginName}" plugin is not implemented on ${platform}`, ExceptionCode.Unimplemented);
                }
            };
            const createPluginMethodWrapper = (prop) => {
                let remove;
                const wrapper = (...args) => {
                    const p = loadPluginImplementation().then((impl) => {
                        const fn = createPluginMethod(impl, prop);
                        if (fn) {
                            const p = fn(...args);
                            remove = p === null || p === void 0 ? void 0 : p.remove;
                            return p;
                        }
                        else {
                            throw new CapacitorException(`"${pluginName}.${prop}()" is not implemented on ${platform}`, ExceptionCode.Unimplemented);
                        }
                    });
                    if (prop === 'addListener') {
                        p.remove = async () => remove();
                    }
                    return p;
                };
                // Some flair ✨
                wrapper.toString = () => `${prop.toString()}() { [capacitor code] }`;
                Object.defineProperty(wrapper, 'name', {
                    value: prop,
                    writable: false,
                    configurable: false,
                });
                return wrapper;
            };
            const addListener = createPluginMethodWrapper('addListener');
            const removeListener = createPluginMethodWrapper('removeListener');
            const addListenerNative = (eventName, callback) => {
                const call = addListener({ eventName }, callback);
                const remove = async () => {
                    const callbackId = await call;
                    removeListener({
                        eventName,
                        callbackId,
                    }, callback);
                };
                const p = new Promise((resolve) => call.then(() => resolve({ remove })));
                p.remove = async () => {
                    console.warn(`Using addListener() without 'await' is deprecated.`);
                    await remove();
                };
                return p;
            };
            const proxy = new Proxy({}, {
                get(_, prop) {
                    switch (prop) {
                        // https://github.com/facebook/react/issues/20030
                        case '$$typeof':
                            return undefined;
                        case 'toJSON':
                            return () => ({});
                        case 'addListener':
                            return pluginHeader ? addListenerNative : addListener;
                        case 'removeListener':
                            return removeListener;
                        default:
                            return createPluginMethodWrapper(prop);
                    }
                },
            });
            Plugins[pluginName] = proxy;
            registeredPlugins.set(pluginName, {
                name: pluginName,
                proxy,
                platforms: new Set([...Object.keys(jsImplementations), ...(pluginHeader ? [platform] : [])]),
            });
            return proxy;
        };
        // Add in convertFileSrc for web, it will already be available in native context
        if (!cap.convertFileSrc) {
            cap.convertFileSrc = (filePath) => filePath;
        }
        cap.getPlatform = getPlatform;
        cap.handleError = handleError;
        cap.isNativePlatform = isNativePlatform;
        cap.isPluginAvailable = isPluginAvailable;
        cap.registerPlugin = registerPlugin;
        cap.Exception = CapacitorException;
        cap.DEBUG = !!cap.DEBUG;
        cap.isLoggingEnabled = !!cap.isLoggingEnabled;
        return cap;
    };
    const initCapacitorGlobal = (win) => (win.Capacitor = createCapacitor(win));

    const Capacitor = /*#__PURE__*/ initCapacitorGlobal(typeof globalThis !== 'undefined'
        ? globalThis
        : typeof self !== 'undefined'
            ? self
            : typeof window !== 'undefined'
                ? window
                : typeof global !== 'undefined'
                    ? global
                    : {});
    const registerPlugin = Capacitor.registerPlugin;

    /**
     * Base class web plugins should extend.
     */
    class WebPlugin {
        constructor() {
            this.listeners = {};
            this.retainedEventArguments = {};
            this.windowListeners = {};
        }
        addListener(eventName, listenerFunc) {
            let firstListener = false;
            const listeners = this.listeners[eventName];
            if (!listeners) {
                this.listeners[eventName] = [];
                firstListener = true;
            }
            this.listeners[eventName].push(listenerFunc);
            // If we haven't added a window listener for this event and it requires one,
            // go ahead and add it
            const windowListener = this.windowListeners[eventName];
            if (windowListener && !windowListener.registered) {
                this.addWindowListener(windowListener);
            }
            if (firstListener) {
                this.sendRetainedArgumentsForEvent(eventName);
            }
            const remove = async () => this.removeListener(eventName, listenerFunc);
            const p = Promise.resolve({ remove });
            return p;
        }
        async removeAllListeners() {
            this.listeners = {};
            for (const listener in this.windowListeners) {
                this.removeWindowListener(this.windowListeners[listener]);
            }
            this.windowListeners = {};
        }
        notifyListeners(eventName, data, retainUntilConsumed) {
            const listeners = this.listeners[eventName];
            if (!listeners) {
                if (retainUntilConsumed) {
                    let args = this.retainedEventArguments[eventName];
                    if (!args) {
                        args = [];
                    }
                    args.push(data);
                    this.retainedEventArguments[eventName] = args;
                }
                return;
            }
            listeners.forEach((listener) => listener(data));
        }
        hasListeners(eventName) {
            var _a;
            return !!((_a = this.listeners[eventName]) === null || _a === void 0 ? void 0 : _a.length);
        }
        registerWindowListener(windowEventName, pluginEventName) {
            this.windowListeners[pluginEventName] = {
                registered: false,
                windowEventName,
                pluginEventName,
                handler: (event) => {
                    this.notifyListeners(pluginEventName, event);
                },
            };
        }
        unimplemented(msg = 'not implemented') {
            return new Capacitor.Exception(msg, ExceptionCode.Unimplemented);
        }
        unavailable(msg = 'not available') {
            return new Capacitor.Exception(msg, ExceptionCode.Unavailable);
        }
        async removeListener(eventName, listenerFunc) {
            const listeners = this.listeners[eventName];
            if (!listeners) {
                return;
            }
            const index = listeners.indexOf(listenerFunc);
            if (index !== -1) {
                this.listeners[eventName].splice(index, 1);
            }
            // If there are no more listeners for this type of event,
            // remove the window listener
            if (!this.listeners[eventName].length) {
                this.removeWindowListener(this.windowListeners[eventName]);
            }
        }
        addWindowListener(handle) {
            window.addEventListener(handle.windowEventName, handle.handler);
            handle.registered = true;
        }
        removeWindowListener(handle) {
            if (!handle) {
                return;
            }
            window.removeEventListener(handle.windowEventName, handle.handler);
            handle.registered = false;
        }
        sendRetainedArgumentsForEvent(eventName) {
            const args = this.retainedEventArguments[eventName];
            if (!args) {
                return;
            }
            delete this.retainedEventArguments[eventName];
            args.forEach((arg) => {
                this.notifyListeners(eventName, arg);
            });
        }
    }
    /******** END WEB VIEW PLUGIN ********/
    /******** COOKIES PLUGIN ********/
    /**
     * Safely web encode a string value (inspired by js-cookie)
     * @param str The string value to encode
     */
    const encode = (str) => encodeURIComponent(str)
        .replace(/%(2[346B]|5E|60|7C)/g, decodeURIComponent)
        .replace(/[()]/g, escape);
    /**
     * Safely web decode a string value (inspired by js-cookie)
     * @param str The string value to decode
     */
    const decode = (str) => str.replace(/(%[\dA-F]{2})+/gi, decodeURIComponent);
    class CapacitorCookiesPluginWeb extends WebPlugin {
        async getCookies() {
            const cookies = document.cookie;
            const cookieMap = {};
            cookies.split(';').forEach((cookie) => {
                if (cookie.length <= 0)
                    return;
                // Replace first "=" with CAP_COOKIE to prevent splitting on additional "="
                let [key, value] = cookie.replace(/=/, 'CAP_COOKIE').split('CAP_COOKIE');
                key = decode(key).trim();
                value = decode(value).trim();
                cookieMap[key] = value;
            });
            return cookieMap;
        }
        async setCookie(options) {
            try {
                // Safely Encoded Key/Value
                const encodedKey = encode(options.key);
                const encodedValue = encode(options.value);
                // Clean & sanitize options
                const expires = options.expires ? `; expires=${options.expires.replace('expires=', '')}` : '';
                const path = (options.path || '/').replace('path=', ''); // Default is "path=/"
                const domain = options.url != null && options.url.length > 0 ? `domain=${options.url}` : '';
                document.cookie = `${encodedKey}=${encodedValue || ''}${expires}; path=${path}; ${domain};`;
            }
            catch (error) {
                return Promise.reject(error);
            }
        }
        async deleteCookie(options) {
            try {
                document.cookie = `${options.key}=; Max-Age=0`;
            }
            catch (error) {
                return Promise.reject(error);
            }
        }
        async clearCookies() {
            try {
                const cookies = document.cookie.split(';') || [];
                for (const cookie of cookies) {
                    document.cookie = cookie.replace(/^ +/, '').replace(/=.*/, `=;expires=${new Date().toUTCString()};path=/`);
                }
            }
            catch (error) {
                return Promise.reject(error);
            }
        }
        async clearAllCookies() {
            try {
                await this.clearCookies();
            }
            catch (error) {
                return Promise.reject(error);
            }
        }
    }
    registerPlugin('CapacitorCookies', {
        web: () => new CapacitorCookiesPluginWeb(),
    });
    // UTILITY FUNCTIONS
    /**
     * Read in a Blob value and return it as a base64 string
     * @param blob The blob value to convert to a base64 string
     */
    const readBlobAsBase64 = async (blob) => new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const base64String = reader.result;
            // remove prefix "data:application/pdf;base64,"
            resolve(base64String.indexOf(',') >= 0 ? base64String.split(',')[1] : base64String);
        };
        reader.onerror = (error) => reject(error);
        reader.readAsDataURL(blob);
    });
    /**
     * Normalize an HttpHeaders map by lowercasing all of the values
     * @param headers The HttpHeaders object to normalize
     */
    const normalizeHttpHeaders = (headers = {}) => {
        const originalKeys = Object.keys(headers);
        const loweredKeys = Object.keys(headers).map((k) => k.toLocaleLowerCase());
        const normalized = loweredKeys.reduce((acc, key, index) => {
            acc[key] = headers[originalKeys[index]];
            return acc;
        }, {});
        return normalized;
    };
    /**
     * Builds a string of url parameters that
     * @param params A map of url parameters
     * @param shouldEncode true if you should encodeURIComponent() the values (true by default)
     */
    const buildUrlParams = (params, shouldEncode = true) => {
        if (!params)
            return null;
        const output = Object.entries(params).reduce((accumulator, entry) => {
            const [key, value] = entry;
            let encodedValue;
            let item;
            if (Array.isArray(value)) {
                item = '';
                value.forEach((str) => {
                    encodedValue = shouldEncode ? encodeURIComponent(str) : str;
                    item += `${key}=${encodedValue}&`;
                });
                // last character will always be "&" so slice it off
                item.slice(0, -1);
            }
            else {
                encodedValue = shouldEncode ? encodeURIComponent(value) : value;
                item = `${key}=${encodedValue}`;
            }
            return `${accumulator}&${item}`;
        }, '');
        // Remove initial "&" from the reduce
        return output.substr(1);
    };
    /**
     * Build the RequestInit object based on the options passed into the initial request
     * @param options The Http plugin options
     * @param extra Any extra RequestInit values
     */
    const buildRequestInit = (options, extra = {}) => {
        const output = Object.assign({ method: options.method || 'GET', headers: options.headers }, extra);
        // Get the content-type
        const headers = normalizeHttpHeaders(options.headers);
        const type = headers['content-type'] || '';
        // If body is already a string, then pass it through as-is.
        if (typeof options.data === 'string') {
            output.body = options.data;
        }
        // Build request initializers based off of content-type
        else if (type.includes('application/x-www-form-urlencoded')) {
            const params = new URLSearchParams();
            for (const [key, value] of Object.entries(options.data || {})) {
                params.set(key, value);
            }
            output.body = params.toString();
        }
        else if (type.includes('multipart/form-data') || options.data instanceof FormData) {
            const form = new FormData();
            if (options.data instanceof FormData) {
                options.data.forEach((value, key) => {
                    form.append(key, value);
                });
            }
            else {
                for (const key of Object.keys(options.data)) {
                    form.append(key, options.data[key]);
                }
            }
            output.body = form;
            const headers = new Headers(output.headers);
            headers.delete('content-type'); // content-type will be set by `window.fetch` to includy boundary
            output.headers = headers;
        }
        else if (type.includes('application/json') || typeof options.data === 'object') {
            output.body = JSON.stringify(options.data);
        }
        return output;
    };
    // WEB IMPLEMENTATION
    class CapacitorHttpPluginWeb extends WebPlugin {
        /**
         * Perform an Http request given a set of options
         * @param options Options to build the HTTP request
         */
        async request(options) {
            const requestInit = buildRequestInit(options, options.webFetchExtra);
            const urlParams = buildUrlParams(options.params, options.shouldEncodeUrlParams);
            const url = urlParams ? `${options.url}?${urlParams}` : options.url;
            const response = await fetch(url, requestInit);
            const contentType = response.headers.get('content-type') || '';
            // Default to 'text' responseType so no parsing happens
            let { responseType = 'text' } = response.ok ? options : {};
            // If the response content-type is json, force the response to be json
            if (contentType.includes('application/json')) {
                responseType = 'json';
            }
            let data;
            let blob;
            switch (responseType) {
                case 'arraybuffer':
                case 'blob':
                    blob = await response.blob();
                    data = await readBlobAsBase64(blob);
                    break;
                case 'json':
                    data = await response.json();
                    break;
                case 'document':
                case 'text':
                default:
                    data = await response.text();
            }
            // Convert fetch headers to Capacitor HttpHeaders
            const headers = {};
            response.headers.forEach((value, key) => {
                headers[key] = value;
            });
            return {
                data,
                headers,
                status: response.status,
                url: response.url,
            };
        }
        /**
         * Perform an Http GET request given a set of options
         * @param options Options to build the HTTP request
         */
        async get(options) {
            return this.request(Object.assign(Object.assign({}, options), { method: 'GET' }));
        }
        /**
         * Perform an Http POST request given a set of options
         * @param options Options to build the HTTP request
         */
        async post(options) {
            return this.request(Object.assign(Object.assign({}, options), { method: 'POST' }));
        }
        /**
         * Perform an Http PUT request given a set of options
         * @param options Options to build the HTTP request
         */
        async put(options) {
            return this.request(Object.assign(Object.assign({}, options), { method: 'PUT' }));
        }
        /**
         * Perform an Http PATCH request given a set of options
         * @param options Options to build the HTTP request
         */
        async patch(options) {
            return this.request(Object.assign(Object.assign({}, options), { method: 'PATCH' }));
        }
        /**
         * Perform an Http DELETE request given a set of options
         * @param options Options to build the HTTP request
         */
        async delete(options) {
            return this.request(Object.assign(Object.assign({}, options), { method: 'DELETE' }));
        }
    }
    registerPlugin('CapacitorHttp', {
        web: () => new CapacitorHttpPluginWeb(),
    });
    /******** END HTTP PLUGIN ********/
    /******** SYSTEM BARS PLUGIN ********/
    /**
     * Available status bar styles.
     */
    var SystemBarsStyle;
    (function (SystemBarsStyle) {
        /**
         * Light system bar content on a dark background.
         *
         * @since 8.0.0
         */
        SystemBarsStyle["Dark"] = "DARK";
        /**
         * For dark system bar content on a light background.
         *
         * @since 8.0.0
         */
        SystemBarsStyle["Light"] = "LIGHT";
        /**
         * The style is based on the device appearance or the underlying content.
         * If the device is using Dark mode, the system bars content will be light.
         * If the device is using Light mode, the system bars content will be dark.
         *
         * @since 8.0.0
         */
        SystemBarsStyle["Default"] = "DEFAULT";
    })(SystemBarsStyle || (SystemBarsStyle = {}));
    /**
     * Available system bar types.
     */
    var SystemBarType;
    (function (SystemBarType) {
        /**
         * The top status bar on both Android and iOS.
         *
         * @since 8.0.0
         */
        SystemBarType["StatusBar"] = "StatusBar";
        /**
         * The navigation bar (or gesture bar on iOS) on both Android and iOS.
         *
         * @since 8.0.0
         */
        SystemBarType["NavigationBar"] = "NavigationBar";
    })(SystemBarType || (SystemBarType = {}));
    class SystemBarsPluginWeb extends WebPlugin {
        async setStyle() {
            this.unavailable('not available for web');
        }
        async setAnimation() {
            this.unavailable('not available for web');
        }
        async show() {
            this.unavailable('not available for web');
        }
        async hide() {
            this.unavailable('not available for web');
        }
    }
    registerPlugin('SystemBars', {
        web: () => new SystemBarsPluginWeb(),
    });

    const App = registerPlugin('App', {
        web: () => Promise.resolve().then(function () { return web$3; }).then((m) => new m.AppWeb()),
    });

    const Browser = registerPlugin('Browser', {
        web: () => Promise.resolve().then(function () { return web$2; }).then((m) => new m.BrowserWeb()),
    });

    function s(t) {
      t.CapacitorUtils.Synapse = new Proxy(
        {},
        {
          get(e, n) {
            return new Proxy({}, {
              get(w, o) {
                return (c, p, r) => {
                  const i = t.Capacitor.Plugins[n];
                  if (i === void 0) {
                    r(new Error(`Capacitor plugin ${n} not found`));
                    return;
                  }
                  if (typeof i[o] != "function") {
                    r(new Error(`Method ${o} not found in Capacitor plugin ${n}`));
                    return;
                  }
                  (async () => {
                    try {
                      const a = await i[o](c);
                      p(a);
                    } catch (a) {
                      r(a);
                    }
                  })();
                };
              }
            });
          }
        }
      );
    }
    function u(t) {
      t.CapacitorUtils.Synapse = new Proxy(
        {},
        {
          get(e, n) {
            return t.cordova.plugins[n];
          }
        }
      );
    }
    function f(t = false) {
      typeof window > "u" || (window.CapacitorUtils = window.CapacitorUtils || {}, window.Capacitor !== void 0 && !t ? s(window) : window.cordova !== void 0 && u(window));
    }

    const Geolocation = registerPlugin('Geolocation', {
        web: () => Promise.resolve().then(function () { return web$1; }).then((m) => new m.GeolocationWeb()),
    });
    f();

    const Share = registerPlugin('Share', {
        web: () => Promise.resolve().then(function () { return web; }).then((m) => new m.ShareWeb()),
    });

    const PushNotifications = registerPlugin('PushNotifications', {});

    if (Capacitor.isNativePlatform()) {
      const emit = (name, detail) => window.dispatchEvent(new CustomEvent(name, { detail }));
      let installed = false;
      let pending = null;
      window.SwiftPush = {
        async enable() {
          if (!window.SWIFTSHOP_PUSH_ENABLED) throw Error('Delivery push setup is not complete yet.');
          if (!installed) {
            await PushNotifications.addListener('registration', ({ value }) => {
              const token={ token:value, platform:Capacitor.getPlatform() };
              pending?.resolve(token); emit('swift-push-token',token);
            });
            await PushNotifications.addListener('registrationError', error => {
              const message=error.error || 'Could not register notifications.';
              pending?.reject(Error(message)); emit('swift-push-error',{message});
            });
            await PushNotifications.addListener('pushNotificationReceived', notification => emit('swift-delivery-push', notification));
            await PushNotifications.addListener('pushNotificationActionPerformed', ({ notification }) => emit('swift-delivery-push-open', notification));
            installed = true;
          }
          let permission = await PushNotifications.checkPermissions();
          if (permission.receive === 'prompt' || permission.receive === 'prompt-with-rationale') permission = await PushNotifications.requestPermissions();
          if (permission.receive !== 'granted') throw Error('Notifications are disabled. Allow them in your phone settings.');
          if (Capacitor.getPlatform() === 'android') await PushNotifications.createChannel({ id: 'delivery-updates', name: 'Delivery updates', description: 'Order acceptance, preparation and delivery updates', importance: 4, visibility: 0, sound: 'default' });
          if(Capacitor.getPlatform()==='android')await PushNotifications.createChannel({id:'swiftshop-promotions',name:'SwiftShop offers',description:'Optional promotions and announcements',importance:3,visibility:0,sound:'default'});
          if(pending) return pending.promise;
          let resolve,reject;
          const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});
          const timeout=setTimeout(()=>reject(Error('Notification registration timed out. Check your connection and try again.')),20000);
          pending={promise,resolve,reject};
          try {
            await PushNotifications.register().catch(reject);
            return await promise;
          } finally {clearTimeout(timeout);pending=null;}
        },
        async disable() { if (!window.SWIFTSHOP_PUSH_ENABLED) return; await PushNotifications.unregister(); await PushNotifications.removeAllDeliveredNotifications(); }
      };
    }

    if (Capacitor.isNativePlatform()) {
      document.documentElement.classList.add('native-app');
      const webOpen = window.open.bind(window);
      window.open = function (value, target, features) {
        let url;
        try { url = new URL(value, location.href); } catch { return null; }
        if (url.origin === location.origin) return webOpen(value, target, features);
        if (!['https:', 'http:', 'tel:', 'mailto:'].includes(url.protocol)) return null;
        if (['tel:', 'mailto:'].includes(url.protocol)) location.href = url.href;
        else Browser.open({ url: url.href }).catch(() => alert('Could not open the link. Please try again.'));
        return null;
      };
      document.addEventListener('click', event => {
        const anchor = event.target.closest?.('a[href]');
        if (!anchor || event.defaultPrevented) return;
        const url = new URL(anchor.href, location.href);
        if (url.origin !== location.origin && ['http:', 'https:', 'tel:', 'mailto:'].includes(url.protocol)) {
          event.preventDefault(); window.open(url.href, '_blank');
        }
      });
      const geo = {
        getCurrentPosition(success, failure, options = {}) {
          Geolocation.getCurrentPosition({ enableHighAccuracy: !!options.enableHighAccuracy, timeout: options.timeout ?? 15000, maximumAge: options.maximumAge ?? 0 })
            .then(success).catch(error => failure?.({ code: error.code === 'OS-PLUG-GLOC-0003' ? 1 : 2, message: error.message }));
        },
        watchPosition(success, failure, options = {}) {
          const token = ++geo.sequence;
          const pending = Geolocation.watchPosition(options, (position, error) => position ? success(position) : failure?.(error));
          geo.watches.set(token, pending); return token;
        },
        clearWatch(token) { const pending = geo.watches.get(token); if (pending) pending.then(id => Geolocation.clearWatch({ id })).catch(() => {}); geo.watches.delete(token); },
        sequence: 0, watches: new Map()
      };
      Object.defineProperty(navigator, 'geolocation', { configurable: true, value: geo });
      Object.defineProperty(navigator, 'share', { configurable: true, value: async data => {
        if (data.url && new URL(data.url).origin === location.origin) {
          const base = window.SWIFTSHOP_PUBLIC_URL;
          if (!base) { throw new Error('A public customer website is required to share this link.'); }
          const url = new URL(base); const source=new URL(data.url); url.search=source.search; url.hash=source.hash; data = { ...data, url: url.href };
        }
        try { await Share.share({ title: data.title, text: data.text, url: data.url, dialogTitle: 'Share SwiftShop' }); }
        catch (error) { if (/cancel|dismiss/i.test(error.message || '')) throw new DOMException('Share cancelled', 'AbortError'); throw error; }
      }});
      App.addListener('backButton', ({ canGoBack }) => {
        if (window.SwiftNavigation?.back()) return;
        if (canGoBack) history.back();
        else if (confirm('Close SwiftShop?')) App.exitApp();
      });
    }

    class AppWeb extends WebPlugin {
        constructor() {
            super();
            this.handleVisibilityChange = () => {
                const data = {
                    isActive: document.hidden !== true,
                };
                this.notifyListeners('appStateChange', data);
                if (document.hidden) {
                    this.notifyListeners('pause', null);
                }
                else {
                    this.notifyListeners('resume', null);
                }
            };
            document.addEventListener('visibilitychange', this.handleVisibilityChange, false);
        }
        exitApp() {
            throw this.unimplemented('Not implemented on web.');
        }
        async getInfo() {
            throw this.unimplemented('Not implemented on web.');
        }
        async getLaunchUrl() {
            return { url: '' };
        }
        async getState() {
            return { isActive: document.hidden !== true };
        }
        async minimizeApp() {
            throw this.unimplemented('Not implemented on web.');
        }
        async toggleBackButtonHandler() {
            throw this.unimplemented('Not implemented on web.');
        }
        async getAppLanguage() {
            return {
                value: navigator.language.split('-')[0].toLowerCase(),
            };
        }
    }

    var web$3 = /*#__PURE__*/Object.freeze({
        __proto__: null,
        AppWeb: AppWeb
    });

    class BrowserWeb extends WebPlugin {
        constructor() {
            super();
            this._lastWindow = null;
        }
        async open(options) {
            this._lastWindow = window.open(options.url, options.windowName || '_blank');
        }
        async close() {
            return new Promise((resolve, reject) => {
                if (this._lastWindow != null) {
                    this._lastWindow.close();
                    this._lastWindow = null;
                    resolve();
                }
                else {
                    reject('No active window to close!');
                }
            });
        }
    }
    new BrowserWeb();

    var web$2 = /*#__PURE__*/Object.freeze({
        __proto__: null,
        BrowserWeb: BrowserWeb
    });

    class GeolocationWeb extends WebPlugin {
        constructor() {
            super();
            this.latestOrientation = null;
            if (typeof window !== 'undefined') {
                const win = window;
                if ('ondeviceorientationabsolute' in win) {
                    win.addEventListener('deviceorientationabsolute', (event) => this.updateOrientation(event, true), true);
                }
                else if ('ondeviceorientation' in win) {
                    win.addEventListener('deviceorientation', (event) => this.updateOrientation(event, false), true);
                }
            }
        }
        updateOrientation(event, isAbsolute) {
            let trueHeading = null;
            let magneticHeading = null;
            let headingAccuracy = null;
            if (isAbsolute && event.alpha !== null) {
                trueHeading = (360 - event.alpha) % 360;
            }
            else if (event.webkitCompassHeading !== undefined && event.webkitCompassHeading !== null) {
                magneticHeading = event.webkitCompassHeading;
                headingAccuracy = event.webkitCompassAccuracy;
            }
            else if (event.alpha !== null && event.absolute === true) {
                trueHeading = (360 - event.alpha) % 360;
            }
            else if (event.alpha !== null) {
                magneticHeading = (360 - event.alpha) % 360;
            }
            if (trueHeading !== null || magneticHeading !== null) {
                this.latestOrientation = {
                    trueHeading,
                    magneticHeading,
                    headingAccuracy,
                };
            }
        }
        augmentPosition(pos, isWatch = false) {
            var _a, _b, _c, _d, _e, _f, _g;
            const coords = pos.coords;
            const orientation = isWatch ? this.latestOrientation : null;
            const heading = (_c = (_b = (_a = orientation === null || orientation === void 0 ? void 0 : orientation.trueHeading) !== null && _a !== void 0 ? _a : orientation === null || orientation === void 0 ? void 0 : orientation.magneticHeading) !== null && _b !== void 0 ? _b : (isWatch ? coords.heading : null)) !== null && _c !== void 0 ? _c : null;
            return {
                timestamp: pos.timestamp,
                coords: {
                    latitude: coords.latitude,
                    longitude: coords.longitude,
                    accuracy: coords.accuracy,
                    altitude: coords.altitude,
                    altitudeAccuracy: coords.altitudeAccuracy,
                    speed: coords.speed,
                    heading: heading,
                    magneticHeading: (_d = orientation === null || orientation === void 0 ? void 0 : orientation.magneticHeading) !== null && _d !== void 0 ? _d : null,
                    trueHeading: (_e = orientation === null || orientation === void 0 ? void 0 : orientation.trueHeading) !== null && _e !== void 0 ? _e : null,
                    headingAccuracy: (_f = orientation === null || orientation === void 0 ? void 0 : orientation.headingAccuracy) !== null && _f !== void 0 ? _f : null,
                    course: (_g = (isWatch ? coords.heading : null)) !== null && _g !== void 0 ? _g : null,
                },
            };
        }
        async getCurrentPosition(options) {
            return new Promise((resolve, reject) => {
                navigator.geolocation.getCurrentPosition((pos) => {
                    resolve(this.augmentPosition(pos, false));
                }, (err) => {
                    reject(err);
                }, Object.assign({ enableHighAccuracy: false, timeout: 10000, maximumAge: 0 }, options));
            });
        }
        async watchPosition(options, callback) {
            const id = navigator.geolocation.watchPosition((pos) => {
                callback(this.augmentPosition(pos, true));
            }, (err) => {
                callback(null, err);
            }, Object.assign({ enableHighAccuracy: false, timeout: 10000, maximumAge: 0, minimumUpdateInterval: 5000 }, options));
            return `${id}`;
        }
        async clearWatch(options) {
            navigator.geolocation.clearWatch(parseInt(options.id, 10));
        }
        async checkPermissions() {
            if (typeof navigator === 'undefined' || !navigator.permissions) {
                throw this.unavailable('Permissions API not available in this browser');
            }
            const permission = await navigator.permissions.query({
                name: 'geolocation',
            });
            return { location: permission.state, coarseLocation: permission.state };
        }
        async requestPermissions() {
            throw this.unimplemented('Not implemented on web.');
        }
    }
    new GeolocationWeb();

    var web$1 = /*#__PURE__*/Object.freeze({
        __proto__: null,
        GeolocationWeb: GeolocationWeb
    });

    class ShareWeb extends WebPlugin {
        async canShare() {
            if (typeof navigator === 'undefined' || !navigator.share) {
                return { value: false };
            }
            else {
                return { value: true };
            }
        }
        async share(options) {
            if (typeof navigator === 'undefined' || !navigator.share) {
                throw this.unavailable('Share API not available in this browser');
            }
            await navigator.share({
                title: options.title,
                text: options.text,
                url: options.url,
            });
            return {};
        }
    }

    var web = /*#__PURE__*/Object.freeze({
        __proto__: null,
        ShareWeb: ShareWeb
    });

})();
