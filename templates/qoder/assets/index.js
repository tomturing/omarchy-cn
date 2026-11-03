'use strict';
const path = require('path');
const { createWrapper } = require('./wrapper');

let binding;
try {
  binding = require('./build/Release/watcher.node');
} catch (err) {
  try {
    binding = require(path.join(__dirname, 'build/Release/watcher.node'));
  } catch (err2) {
    console.error('[watcher-hardened] Failed to load binary watcher.node:', err2);
    throw err2;
  }
}

const wrapper = createWrapper(binding);
exports.writeSnapshot = wrapper.writeSnapshot;
exports.getEventsSince = wrapper.getEventsSince;
exports.subscribe = wrapper.subscribe;
exports.unsubscribe = wrapper.unsubscribe;
