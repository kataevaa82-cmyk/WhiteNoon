(function () {
  "use strict";

  var listeners = {};
  var storageKey = "white_noon_pages_cloud_mock";

  function readData() {
    try {
      return JSON.parse(window.localStorage.getItem(storageKey) || "{}");
    } catch (error) {
      console.warn("Pages save mock:", error);
      return {};
    }
  }

  var player = {
    isAuthorized: function () { return false; },
    getData: async function (keys) {
      var data = readData();
      if (!Array.isArray(keys)) return data;
      return keys.reduce(function (selected, key) {
        if (Object.prototype.hasOwnProperty.call(data, key)) selected[key] = data[key];
        return selected;
      }, {});
    },
    setData: async function (data) {
      var merged = Object.assign(readData(), data || {});
      window.localStorage.setItem(storageKey, JSON.stringify(merged));
    }
  };

  var sdk = {
    environment: {
      i18n: { lang: (navigator.language || "ru").split("-")[0].toLowerCase() }
    },
    features: {
      LoadingAPI: { ready: function () {
        var loaderHidden = !document.getElementById("status") && window.whiteNoonLoaderHidden === true;
        var readyCount = Number(document.documentElement.dataset.gameReadyCount || "0") + 1;
        document.documentElement.dataset.gameReadyAfterLoader = String(loaderHidden);
        document.documentElement.dataset.gameReadyCount = String(readyCount);
        console.info("Pages mock: game ready; loader hidden:", loaderHidden, "count:", readyCount);
      } },
      GameplayAPI: {
        start: function () { console.info("Pages mock: gameplay start"); },
        stop: function () { console.info("Pages mock: gameplay stop"); }
      }
    },
    adv: {
      showFullscreenAdv: function (options) {
        var callbacks = (options && options.callbacks) || {};
        if (callbacks.onOpen) callbacks.onOpen();
        window.setTimeout(function () {
          if (callbacks.onClose) callbacks.onClose(false);
        }, 120);
      }
    },
    auth: {
      openAuthDialog: async function () {
        throw new Error("Yandex ID is available only inside Yandex Games");
      }
    },
    getPlayer: async function () { return player; },
    on: function (eventName, handler) {
      if (!listeners[eventName]) listeners[eventName] = [];
      listeners[eventName].push(handler);
    },
    off: function (eventName, handler) {
      listeners[eventName] = (listeners[eventName] || []).filter(function (item) {
        return item !== handler;
      });
    }
  };

  window.YaGames = { init: async function () { return sdk; } };
})();
