'use strict';
/**
 * Qoder IDE CN 文件监听引擎加固加载器 (Runtime Hardening Hook)
 * 拦截对 @parcel/watcher (v2.5.1 并发缺陷版) 的模块请求，
 * 重定向至安全加固的 @parcel/watcher (v2.6.0 全局互斥锁修复版)。
 */

const path = require('path');
const Module = require('module');

const PATCH_DIR = path.resolve(__dirname, 'watcher-2.6.0');
const PATCH_ENTRY = path.join(PATCH_DIR, 'index.js');
const TRACE_ID = process.env.QODER_TRACE_ID || `trace-${process.pid}-${Date.now().toString(36)}`;

const origLoad = Module._load;

let interceptedCount = 0;

Module._load = function (request, parent, isMain) {
    if (request === '@parcel/watcher') {
        interceptedCount++;
        if (process.env.QODER_WATCHER_DEBUG || process.env.ELECTRON_ENABLE_LOGGING) {
            console.error(`[watcher-hardened][${TRACE_ID}][pid:${process.pid}] Intercepted direct require('@parcel/watcher') -> ${PATCH_ENTRY}`);
        }
        return origLoad.call(this, PATCH_ENTRY, parent, isMain);
    }

    if (typeof request === 'string' && request.includes('@parcel/watcher')) {
        // 匹配针对 /usr/lib/qoder-cn-ide/app/node_modules/@parcel/watcher 的绝对路径或相对路径请求
        if (request.includes('/usr/lib/qoder-cn-ide/app/node_modules/@parcel/watcher')) {
            interceptedCount++;
            const subPath = request.replace(/^.*\/@parcel\/watcher\/?/, '');
            const target = subPath ? path.join(PATCH_DIR, subPath) : PATCH_ENTRY;
            if (process.env.QODER_WATCHER_DEBUG || process.env.ELECTRON_ENABLE_LOGGING) {
                console.error(`[watcher-hardened][${TRACE_ID}][pid:${process.pid}] Intercepted absolute path require('${request}') -> ${target}`);
            }
            return origLoad.call(this, target, parent, isMain);
        }
    }

    return origLoad.apply(this, arguments);
};
