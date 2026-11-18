/**
 * SingWallet 跨端数据存储、精确财务运算、SWBK v1 加密备份与 CSV 防注入导出引擎
 * 零外部依赖 IIFE 模块，严格对齐《跨平台架构与数据规范》v1.0
 */
(function (root) {
  'use strict';

  const SWBK_MAGIC = [0x53, 0x57, 0x42, 0x4b]; // 'SWBK'
  const SWBK_VERSION = 1;
  const SWBK_HEADER_SIZE = 46;
  const SWBK_TAG_SIZE = 16;
  const SWBK_DEFAULT_ITERATIONS = 100000;
  const SWBK_MIN_ITERATIONS = 1000;
  const SWBK_MAX_ITERATIONS = 5000000;

  const TX_STORAGE_KEY = 'singwallet_user_transactions';
  const TRASH_STORAGE_KEY = 'singwallet_trash_items';
  const IDB_NAME = 'singwallet_media_db';
  const IDB_VERSION = 1;
  const IDB_STORE_DRAFT_IMAGES = 'draft_images';

  // IndexedDB 不可用时的内存兜底存储
  const memoryDraftImages = new Map();

  function getWebCrypto() {
    if (typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.subtle && typeof globalThis.crypto.getRandomValues === 'function') {
      return globalThis.crypto;
    }
    if (typeof window !== 'undefined' && window.crypto && window.crypto.subtle && typeof window.crypto.getRandomValues === 'function') {
      return window.crypto;
    }
    if (typeof require === 'function') {
      try {
        const nodeCrypto = require('crypto');
        if (nodeCrypto && nodeCrypto.webcrypto && nodeCrypto.webcrypto.subtle) {
          return nodeCrypto.webcrypto;
        }
      } catch (_) {
        // 忽略非 Node 环境加载异常
      }
    }
    throw new Error('当前运行环境不支持 WebCrypto API');
  }

  function encodeUtf8(str) {
    if (typeof TextEncoder !== 'undefined') {
      return new TextEncoder().encode(String(str));
    }
    if (typeof Buffer !== 'undefined') {
      return new Uint8Array(Buffer.from(String(str), 'utf8'));
    }
    throw new Error('当前环境缺少 TextEncoder');
  }

  function decodeUtf8(bytes) {
    if (typeof TextDecoder !== 'undefined') {
      return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    }
    if (typeof Buffer !== 'undefined') {
      return Buffer.from(bytes).toString('utf8');
    }
    throw new Error('当前环境缺少 TextDecoder');
  }

  function toUint8Array(input) {
    if (input instanceof Uint8Array) {
      return input;
    }
    if (input instanceof ArrayBuffer) {
      return new Uint8Array(input);
    }
    if (ArrayBuffer.isView(input)) {
      return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    }
    return null;
  }

  // =========================================================================
  // 1. HTML 转义工具
  // =========================================================================
  function escapeHtml(str) {
    if (str === null || str === undefined) {
      return '';
    }
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // =========================================================================
  // 2. MoneyMath 精确整数“分”财务运算引擎
  // =========================================================================
  const MoneyMath = {
    /**
     * 基于字符串小数点拆分精确计算整数“分”，根治 IEEE-754 浮点精度漂移
     */
    toCents(val) {
      if (val === null || val === undefined || typeof val === 'boolean') {
        return 0;
      }
      let raw;
      if (typeof val === 'number') {
        if (!Number.isFinite(val)) {
          return 0;
        }
        raw = String(val);
      } else {
        raw = String(val).trim();
      }

      if (!raw) {
        return 0;
      }

      // 剥离货币符号、千分位逗号、空白与常见中文/英文币种前缀后缀
      let cleaned = raw
        .replace(/[¥￥$€£,\s]/g, '')
        .replace(/^(?:CNY|RMB|USD)+/i, '')
        .replace(/(?:元|CNY|RMB|USD)+$/i, '');

      if (!cleaned) {
        return 0;
      }

      const match = cleaned.match(/^([+-])?(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$/);
      if (!match) {
        return 0;
      }

      const sign = match[1] === '-' ? -1 : 1;
      let intPart = match[2] !== undefined ? match[2] : '0';
      let fracPart = match[3] !== undefined ? match[3] : (match[4] !== undefined ? match[4] : '');
      const exp = match[5] !== undefined ? parseInt(match[5], 10) : 0;

      if (exp !== 0) {
        const combined = intPart + fracPart;
        const decimalIdx = intPart.length + exp;
        if (decimalIdx <= 0) {
          intPart = '0';
          fracPart = '0'.repeat(-decimalIdx) + combined;
        } else if (decimalIdx >= combined.length) {
          intPart = combined + '0'.repeat(decimalIdx - combined.length);
          fracPart = '';
        } else {
          intPart = combined.slice(0, decimalIdx);
          fracPart = combined.slice(decimalIdx);
        }
      }

      const intVal = Number(intPart);
      if (!Number.isFinite(intVal)) {
        return 0;
      }

      const paddedFrac = (fracPart + '000').slice(0, 3);
      const centDigits = Number(paddedFrac.slice(0, 2));
      const roundDigit = paddedFrac.charCodeAt(2) - 48;

      let totalAbsCents = intVal * 100 + centDigits + (roundDigit >= 5 ? 1 : 0);
      if (!Number.isSafeInteger(totalAbsCents)) {
        return 0;
      }

      const result = sign * totalAbsCents;
      return result === 0 ? 0 : result;
    },

    centsToYuan(cents) {
      const rounded = Math.round(Number(cents) || 0);
      const safe = rounded === 0 ? 0 : rounded;
      const sign = safe < 0 ? '-' : '';
      const abs = Math.abs(safe);
      const yuan = Math.floor(abs / 100);
      const fen = String(abs % 100).padStart(2, '0');
      return `${sign}${yuan}.${fen}`;
    },

    centsToNumber(cents) {
      return Number((Math.round(Number(cents) || 0) / 100).toFixed(2));
    },

    isIncomeTx(tx) {
      return Boolean(
        tx && (
          tx.type === 'income' ||
          tx.isIncome === true ||
          [tx.cat, tx.category, tx.catName].includes('工资收入')
        )
      );
    },

    isRefundTx(tx) {
      return Boolean(tx && (tx.type === 'refund' || tx.isRefund === true));
    },

    summarizeTransactions(txList) {
      const list = Array.isArray(txList) ? txList : [];
      let expenseCents = 0;
      let incomeCents = 0;
      let refundCents = 0;
      let activeCount = 0;

      for (let i = 0; i < list.length; i++) {
        const tx = list[i];
        if (!tx || typeof tx !== 'object' || tx.softDeleted || tx.trashed) {
          continue;
        }
        const rawVal = (tx.amount != null && tx.amount !== '')
          ? tx.amount
          : (Number(tx.amountInCents || 0) / 100);
        const cents = Math.abs(MoneyMath.toCents(rawVal));

        if (MoneyMath.isRefundTx(tx)) {
          refundCents += cents;
        } else if (MoneyMath.isIncomeTx(tx)) {
          incomeCents += cents;
        } else if (tx.type !== 'transfer') {
          expenseCents += cents;
        }
        activeCount += 1;
      }

      return {
        expenseCents,
        incomeCents,
        refundCents,
        netExpenseCents: expenseCents - incomeCents - refundCents,
        activeCount
      };
    }
  };

  // =========================================================================
  // 3. SwbkCrypto 跨端加密备份容器引擎 (SWBK v1)
  // =========================================================================
  const SwbkCrypto = {
    MAGIC: 'SWBK',
    VERSION: SWBK_VERSION,
    HEADER_SIZE: SWBK_HEADER_SIZE,
    TAG_SIZE: SWBK_TAG_SIZE,
    DEFAULT_ITERATIONS: SWBK_DEFAULT_ITERATIONS,

    isSwbkBinary(bytes) {
      const arr = toUint8Array(bytes);
      if (!arr || arr.length < 6) {
        return false;
      }
      return (
        arr[0] === SWBK_MAGIC[0] &&
        arr[1] === SWBK_MAGIC[1] &&
        arr[2] === SWBK_MAGIC[2] &&
        arr[3] === SWBK_MAGIC[3] &&
        arr[4] === 0x00 &&
        arr[5] === 0x01
      );
    },

    bytesToBase64(uint8) {
      const bytes = toUint8Array(uint8);
      if (!bytes) {
        throw new Error('bytesToBase64 参数必须是 Uint8Array 或 ArrayBuffer');
      }
      if (typeof btoa === 'function') {
        const CHUNK_SIZE = 8192;
        const parts = [];
        for (let i = 0; i < bytes.length; i += CHUNK_SIZE) {
          const slice = bytes.subarray(i, Math.min(i + CHUNK_SIZE, bytes.length));
          parts.push(String.fromCharCode.apply(null, slice));
        }
        return btoa(parts.join(''));
      }
      if (typeof Buffer !== 'undefined') {
        return Buffer.from(bytes).toString('base64');
      }
      throw new Error('当前环境不支持 Base64 编码');
    },

    base64ToBytes(b64) {
      if (typeof b64 !== 'string') {
        throw new Error('base64ToBytes 参数必须是字符串');
      }
      const normalized = b64.trim().replace(/-/g, '+').replace(/_/g, '/');
      if (typeof atob === 'function') {
        const binStr = atob(normalized);
        const out = new Uint8Array(binStr.length);
        for (let i = 0; i < binStr.length; i++) {
          out[i] = binStr.charCodeAt(i);
        }
        return out;
      }
      if (typeof Buffer !== 'undefined') {
        return new Uint8Array(Buffer.from(normalized, 'base64'));
      }
      throw new Error('当前环境不支持 Base64 解码');
    },

    async packSwbkV1(payloadObj, password, iterations = SWBK_DEFAULT_ITERATIONS) {
      if (typeof password !== 'string' || password.length === 0) {
        throw new Error('加密口令不能为空');
      }
      const iters = Number(iterations);
      if (!Number.isInteger(iters) || iters < SWBK_MIN_ITERATIONS || iters > SWBK_MAX_ITERATIONS) {
        throw new Error(`PBKDF2 迭代次数必须为 [${SWBK_MIN_ITERATIONS}, ${SWBK_MAX_ITERATIONS}] 范围内的整数`);
      }
      if (payloadObj === undefined) {
        throw new Error('备份载荷不能为空');
      }

      const webCrypto = getWebCrypto();
      const plainBytes = encodeUtf8(JSON.stringify(payloadObj));

      const salt = new Uint8Array(16);
      const iv = new Uint8Array(12);
      webCrypto.getRandomValues(salt);
      webCrypto.getRandomValues(iv);

      // AAD 固定为前 6 字节: 'SWBK' + Version(0x0001)
      const aad = new Uint8Array([0x53, 0x57, 0x42, 0x4b, 0x00, 0x01]);

      const keyMaterial = await webCrypto.subtle.importKey(
        'raw',
        encodeUtf8(password),
        'PBKDF2',
        false,
        ['deriveKey']
      );

      const aesKey = await webCrypto.subtle.deriveKey(
        {
          name: 'PBKDF2',
          salt: salt,
          iterations: iters,
          hash: 'SHA-256'
        },
        keyMaterial,
        {
          name: 'AES-GCM',
          length: 256
        },
        false,
        ['encrypt']
      );

      const encryptedBuffer = await webCrypto.subtle.encrypt(
        {
          name: 'AES-GCM',
          iv: iv,
          additionalData: aad,
          tagLength: 128
        },
        aesKey,
        plainBytes
      );

      const encryptedAndTag = new Uint8Array(encryptedBuffer);
      if (encryptedAndTag.length < SWBK_TAG_SIZE) {
        throw new Error('AES-GCM 加密输出长度异常');
      }

      const payloadLength = encryptedAndTag.length - SWBK_TAG_SIZE;
      const container = new Uint8Array(SWBK_HEADER_SIZE + encryptedAndTag.length);
      const view = new DataView(container.buffer, container.byteOffset, container.byteLength);

      // 0x00..0x03: Magic 'SWBK'
      container[0] = SWBK_MAGIC[0];
      container[1] = SWBK_MAGIC[1];
      container[2] = SWBK_MAGIC[2];
      container[3] = SWBK_MAGIC[3];
      // 0x04..0x05: Version 0x0001 (uint16 Big-Endian)
      view.setUint16(4, SWBK_VERSION, false);
      // 0x06..0x09: KDF Iterations (uint32 Big-Endian)
      view.setUint32(6, iters, false);
      // 0x0A..0x19: 16B Salt
      container.set(salt, 10);
      // 0x1A..0x25: 12B IV
      container.set(iv, 26);
      // 0x26..0x2D: Ciphertext Payload Length N (uint64 Big-Endian，不含 16B Tag)
      const high32 = Math.floor(payloadLength / 0x100000000);
      const low32 = payloadLength >>> 0;
      view.setUint32(38, high32, false);
      view.setUint32(42, low32, false);
      // 0x2E..(0x2E+N+15): Ciphertext(N) || AuthTag(16)
      container.set(encryptedAndTag, SWBK_HEADER_SIZE);

      return container;
    },

    async unpackSwbkV1(inputBytesOrBuffer, password) {
      if (typeof password !== 'string' || password.length === 0) {
        throw new Error('解密口令不能为空');
      }

      const bytes = toUint8Array(inputBytesOrBuffer);
      if (!bytes) {
        throw new Error('无效的 SWBK 输入类型：需要 Uint8Array 或 ArrayBuffer');
      }
      if (bytes.length < SWBK_HEADER_SIZE + SWBK_TAG_SIZE) {
        throw new Error('无效的 SWBK 备份文件：容器长度不足 62 字节');
      }

      if (
        bytes[0] !== SWBK_MAGIC[0] ||
        bytes[1] !== SWBK_MAGIC[1] ||
        bytes[2] !== SWBK_MAGIC[2] ||
        bytes[3] !== SWBK_MAGIC[3]
      ) {
        throw new Error('无效的 SWBK 备份文件：Magic 标识不是 SWBK');
      }

      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      const version = view.getUint16(4, false);
      if (version !== SWBK_VERSION) {
        throw new Error(`不支持的 SWBK 版本号: v${version}，当前仅支持 v1`);
      }

      const iterations = view.getUint32(6, false);
      if (iterations < SWBK_MIN_ITERATIONS || iterations > SWBK_MAX_ITERATIONS) {
        throw new Error(`无效的 SWBK 备份文件：KDF 迭代次数 (${iterations}) 超出安全范围`);
      }

      const salt = bytes.slice(10, 26);
      const iv = bytes.slice(26, 38);
      const high32 = view.getUint32(38, false);
      const low32 = view.getUint32(42, false);
      const payloadLength = high32 * 0x100000000 + low32;

      if (!Number.isSafeInteger(payloadLength) || bytes.length !== SWBK_HEADER_SIZE + payloadLength + SWBK_TAG_SIZE) {
        throw new Error('SWBK 备份文件校验失败：文件长度与载荷长度字段不匹配或已截断');
      }

      const aad = bytes.slice(0, 6);
      const cipherAndTag = bytes.subarray(SWBK_HEADER_SIZE, SWBK_HEADER_SIZE + payloadLength + SWBK_TAG_SIZE);
      const webCrypto = getWebCrypto();

      const keyMaterial = await webCrypto.subtle.importKey(
        'raw',
        encodeUtf8(password),
        'PBKDF2',
        false,
        ['deriveKey']
      );

      const aesKey = await webCrypto.subtle.deriveKey(
        {
          name: 'PBKDF2',
          salt: salt,
          iterations: iterations,
          hash: 'SHA-256'
        },
        keyMaterial,
        {
          name: 'AES-GCM',
          length: 256
        },
        false,
        ['decrypt']
      );

      let plainBuffer;
      try {
        plainBuffer = await webCrypto.subtle.decrypt(
          {
            name: 'AES-GCM',
            iv: iv,
            additionalData: aad,
            tagLength: 128
          },
          aesKey,
          cipherAndTag
        );
      } catch (_) {
        throw new Error('备份解密失败：口令错误或备份文件已被篡改');
      }

      let jsonText;
      try {
        jsonText = decodeUtf8(new Uint8Array(plainBuffer));
      } catch (_) {
        throw new Error('备份解密失败：明文 UTF-8 编码损坏');
      }

      try {
        return JSON.parse(jsonText);
      } catch (_) {
        throw new Error('备份内容解析失败：解密结果不是有效的 JSON 对象');
      }
    }
  };

  // =========================================================================
  // 4. CsvExporter (RFC 4180 + CSV 公式注入防护 + UTF-8 BOM)
  // =========================================================================
  function collectActiveTransactionsFromMonthly(allMonthlyData) {
    const active = [];
    if (!allMonthlyData) {
      return active;
    }

    if (Array.isArray(allMonthlyData)) {
      for (let i = 0; i < allMonthlyData.length; i++) {
        const tx = allMonthlyData[i];
        if (tx && typeof tx === 'object' && !tx.softDeleted && !tx.trashed) {
          active.push(tx);
        }
      }
      return active;
    }

    if (typeof allMonthlyData === 'object') {
      const monthKeys = Object.keys(allMonthlyData);
      for (let i = 0; i < monthKeys.length; i++) {
        const bucket = allMonthlyData[monthKeys[i]];
        const txs = bucket && Array.isArray(bucket.txs) ? bucket.txs : (Array.isArray(bucket) ? bucket : null);
        if (!txs) {
          continue;
        }
        for (let j = 0; j < txs.length; j++) {
          const tx = txs[j];
          if (tx && typeof tx === 'object' && !tx.softDeleted && !tx.trashed) {
            active.push(tx);
          }
        }
      }
    }
    return active;
  }

  function resolveTxSortTimestamp(tx) {
    if (!tx || typeof tx !== 'object') {
      return '';
    }
    if (tx.txTime) return String(tx.txTime);
    if (tx.orderTime) return String(tx.orderTime);
    if (tx.fullTime) return String(tx.fullTime);
    if (tx.occurred_at) return String(tx.occurred_at);
    const d = tx.date || tx.txDate || tx.occurred_on || '';
    const t = tx.time || tx.timeOnly || '';
    return `${d} ${t}`.trim();
  }

  const CsvExporter = {
    HEADERS: [
      '交易ID',
      '发生日期',
      '发生时间',
      '收支类型',
      '分类',
      '商户名称',
      '金额(元)',
      '支付渠道',
      '支付账户',
      '平台单号',
      '来源规则'
    ],

    sanitizeCsvField(val) {
      if (val === null || val === undefined) {
        return '';
      }
      let text = String(val);
      if (text.length > 0) {
        const first = text.charAt(0);
        if (
          first === '=' ||
          first === '+' ||
          first === '-' ||
          first === '@' ||
          first === '\t' ||
          first === '\r'
        ) {
          text = "'" + text;
        }
      }
      if (/[,"\n\r]/.test(text)) {
        text = '"' + text.replace(/"/g, '""') + '"';
      }
      return text;
    },

    generateTransactionsCsv(allMonthlyData) {
      const activeList = collectActiveTransactionsFromMonthly(allMonthlyData);
      activeList.sort((a, b) => resolveTxSortTimestamp(b).localeCompare(resolveTxSortTimestamp(a)));

      const lines = [CsvExporter.HEADERS.map(CsvExporter.sanitizeCsvField).join(',')];

      for (let i = 0; i < activeList.length; i++) {
        const tx = activeList[i];
        const fullTime = resolveTxSortTimestamp(tx);
        const txDate = tx.date || tx.txDate || tx.occurred_on || (fullTime.length >= 10 ? fullTime.slice(0, 10) : '');
        let txTime = tx.time || tx.timeOnly || '';
        if (!txTime && fullTime.length > 10) {
          txTime = fullTime.slice(11).replace(/Z$/i, '');
        }

        let dirLabel = '支出';
        if (MoneyMath.isRefundTx(tx)) {
          dirLabel = '退款';
        } else if (MoneyMath.isIncomeTx(tx)) {
          dirLabel = '收入';
        } else if (tx.type === 'transfer') {
          dirLabel = '内部转账';
        }

        const catName = tx.cat || tx.category || tx.catName || '';
        const merchantName = tx.merchant || tx.name || tx.merchant_raw || '';
        const rawAmount = (tx.amount != null && tx.amount !== '')
          ? tx.amount
          : (Number(tx.amountInCents || 0) / 100);
        const amountStr = MoneyMath.centsToYuan(Math.abs(MoneyMath.toCents(rawAmount)));
        const channel = tx.channel || (tx.payment && tx.payment.channel) || tx.payment_channel || '';
        const account = tx.account || (tx.payment && (tx.payment.display_name || tx.payment.sub_type)) || '';
        const orderId = tx.orderId || tx.order_id || tx.orderNo || tx.platform_transaction_no || '';
        const sourceRule = tx.sourceRule || tx.ruleName || tx.classificationRule || tx.source || '';

        const row = [
          tx.id || '',
          txDate,
          txTime,
          dirLabel,
          catName,
          merchantName,
          amountStr,
          channel,
          account,
          orderId,
          sourceRule
        ];
        lines.push(row.map(CsvExporter.sanitizeCsvField).join(','));
      }

      return '\uFEFF' + lines.join('\r\n');
    },

    exportCsvFile(allMonthlyData, fileName) {
      const now = new Date();
      const yyyymmdd = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`;
      const targetName = (typeof fileName === 'string' && fileName.trim())
        ? fileName.trim()
        : `singwallet_transactions_${yyyymmdd}.csv`;

      const activeList = collectActiveTransactionsFromMonthly(allMonthlyData);
      const csv = CsvExporter.generateTransactionsCsv(allMonthlyData);
      const count = activeList.length;

      if (typeof root.AndroidBridge !== 'undefined' && root.AndroidBridge && typeof root.AndroidBridge.saveCsvExportFile === 'function') {
        const ok = root.AndroidBridge.saveCsvExportFile(csv, targetName);
        return { ok: ok !== false, csv, count, fileName: targetName };
      }

      if (typeof document !== 'undefined' && typeof Blob !== 'undefined' && typeof URL !== 'undefined' && typeof URL.createObjectURL === 'function') {
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        try {
          const anchor = document.createElement('a');
          anchor.href = url;
          anchor.download = targetName;
          anchor.style.display = 'none';
          if (document.body) {
            document.body.appendChild(anchor);
            anchor.click();
            document.body.removeChild(anchor);
          } else {
            anchor.click();
          }
        } finally {
          setTimeout(() => {
            try { URL.revokeObjectURL(url); } catch (_) {}
          }, 1000);
        }
      }

      return { ok: true, csv, count, fileName: targetName };
    }
  };

  // =========================================================================
  // 5. LedgerStorage (SQLite/localStorage 双模适配器 + IndexedDB + 四层防重)
  // =========================================================================
  function isQuotaExceededError(err) {
    if (!err) {
      return false;
    }
    return (
      err.name === 'QuotaExceededError' ||
      err.name === 'NS_ERROR_DOM_QUOTA_REACHED' ||
      err.code === 22 ||
      err.code === 1014 ||
      /quota/i.test(String(err.message || err))
    );
  }

  function getLocalStorageSafe() {
    try {
      if (typeof localStorage !== 'undefined' && localStorage) {
        return localStorage;
      }
    } catch (_) {
      // 无痕模式或沙箱禁用 localStorage
    }
    return null;
  }

  function openMediaDb() {
    return new Promise((resolve) => {
      if (typeof indexedDB === 'undefined' || !indexedDB || typeof indexedDB.open !== 'function') {
        resolve(null);
        return;
      }
      try {
        const req = indexedDB.open(IDB_NAME, IDB_VERSION);
        req.onupgradeneeded = function (event) {
          const db = event.target.result;
          if (!db.objectStoreNames.contains(IDB_STORE_DRAFT_IMAGES)) {
            db.createObjectStore(IDB_STORE_DRAFT_IMAGES);
          }
        };
        req.onsuccess = function (event) {
          resolve(event.target.result);
        };
        req.onerror = function () {
          resolve(null);
        };
        req.onblocked = function () {
          resolve(null);
        };
      } catch (_) {
        resolve(null);
      }
    });
  }

  function cloneAndRedact(value, seen) {
    if (value === null || value === undefined || typeof value !== 'object') {
      return value;
    }
    if (seen.has(value)) {
      return null;
    }
    seen.add(value);

    if (Array.isArray(value)) {
      return value.map((item) => cloneAndRedact(item, seen));
    }

    const out = {};
    const keys = Object.keys(value);
    const sensitiveKeys = new Set([
      'apiKey',
      'api_key',
      'githubToken',
      'github_token',
      'token',
      'accessToken',
      'refreshToken',
      'secretKey'
    ]);

    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (sensitiveKeys.has(k)) {
        out[k] = typeof value[k] === 'string' ? '' : null;
      } else {
        out[k] = cloneAndRedact(value[k], seen);
      }
    }
    return out;
  }

  function normalizeMerchantForDedup(rawName) {
    if (rawName === null || rawName === undefined) {
      return '';
    }
    return String(rawName)
      .trim()
      .toLowerCase()
      .replace(/[\s\-_·・.,，。()（）【】[\]'"“”‘’]+/g, '');
  }

  function parseTimestampMs(tx) {
    const raw = resolveTxSortTimestamp(tx);
    if (!raw) {
      return NaN;
    }
    const normalized = raw.trim().replace(/\//g, '-');
    // 纯日期 YYYY-MM-DD 补齐本地零点，避免 Date.parse 按 UTC 与带时分秒的本地时间产生 8 小时偏差
    if (/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
      return Date.parse(`${normalized}T00:00:00`);
    }
    if (/^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(:\d{2})?$/.test(normalized)) {
      const isoLocal = normalized.replace(/\s+/, 'T');
      return Date.parse(isoLocal.length === 16 ? `${isoLocal}:00` : isoLocal);
    }
    return Date.parse(normalized);
  }

  const LedgerStorage = {
    saveTransactions(txArray) {
      const payload = Array.isArray(txArray) ? txArray : [];
      const json = JSON.stringify(payload);
      const bridge = root.AndroidBridge;
      const hasNativeDb = Boolean(bridge && typeof bridge.dbSaveTransactionsJson === 'function');
      let sqliteOk = false;
      let sqliteError = null;

      if (hasNativeDb) {
        try {
          const res = bridge.dbSaveTransactionsJson(json);
          sqliteOk = res !== false;
        } catch (err) {
          sqliteError = String(err);
        }
      }

      const ls = getLocalStorageSafe();
      if (ls) {
        try {
          ls.setItem(TX_STORAGE_KEY, json);
          return {
            ok: true,
            sqlite: sqliteOk,
            localStorage: true,
            count: payload.length
          };
        } catch (err) {
          const quota = isQuotaExceededError(err);
          if (sqliteOk) {
            return {
              ok: true,
              sqlite: true,
              localStorage: false,
              quotaExceeded: quota,
              count: payload.length
            };
          }
          return {
            ok: false,
            quotaExceeded: quota,
            error: String(err)
          };
        }
      }

      if (hasNativeDb) {
        return sqliteOk
          ? { ok: true, sqlite: true, localStorage: false, count: payload.length }
          : { ok: false, quotaExceeded: false, error: sqliteError || '原生 SQLite 写入失败' };
      }

      return {
        ok: false,
        quotaExceeded: false,
        error: '当前环境无可用持久化存储 (localStorage / SQLite)'
      };
    },

    loadTransactions() {
      const bridge = root.AndroidBridge;
      const hasNativeLoad = Boolean(bridge && typeof bridge.dbLoadTransactionsJson === 'function');
      const ls = getLocalStorageSafe();

      if (hasNativeLoad) {
        try {
          const nativeRaw = bridge.dbLoadTransactionsJson();
          if (typeof nativeRaw === 'string' && nativeRaw.trim().length > 0) {
            const parsedNative = JSON.parse(nativeRaw);
            if (Array.isArray(parsedNative)) {
              return parsedNative;
            }
          }
        } catch (_) {
          // 若原生返回异常 JSON，继续检查 localStorage 迁移兜底
        }

        // 原生返回空串时，检查 localStorage 历史数据并执行一次性无损迁移
        if (ls) {
          try {
            const localRaw = ls.getItem(TX_STORAGE_KEY);
            if (typeof localRaw === 'string' && localRaw.trim().length > 0) {
              const parsedLocal = JSON.parse(localRaw);
              if (Array.isArray(parsedLocal)) {
                if (typeof bridge.dbSaveTransactionsJson === 'function') {
                  try {
                    bridge.dbSaveTransactionsJson(localRaw);
                  } catch (_) {
                    // 迁移写入失败不影响当次读取返回
                  }
                }
                return parsedLocal;
              }
            }
          } catch (_) {
            return [];
          }
        }
        return [];
      }

      if (ls) {
        try {
          const localRaw = ls.getItem(TX_STORAGE_KEY);
          if (typeof localRaw === 'string' && localRaw.trim().length > 0) {
            const parsed = JSON.parse(localRaw);
            return Array.isArray(parsed) ? parsed : [];
          }
        } catch (_) {
          return [];
        }
      }
      return [];
    },

    saveTrashItems(items) {
      const now = Date.now();
      const list = Array.isArray(items) ? items : [];
      const normalized = list.map((item) => {
        if (!item || typeof item !== 'object') {
          return item;
        }
        const ts = Number(item.deletedAt);
        return Object.assign({}, item, {
          deletedAt: (item.deletedAt != null && Number.isFinite(ts) && ts > 0) ? ts : now
        });
      });

      const json = JSON.stringify(normalized);
      const bridge = root.AndroidBridge;
      const hasNativeKv = Boolean(bridge && typeof bridge.dbSaveKeyValue === 'function');
      let sqliteOk = false;

      if (hasNativeKv) {
        try {
          const res = bridge.dbSaveKeyValue(TRASH_STORAGE_KEY, json);
          sqliteOk = res !== false;
        } catch (_) {
          sqliteOk = false;
        }
      }

      const ls = getLocalStorageSafe();
      if (ls) {
        try {
          ls.setItem(TRASH_STORAGE_KEY, json);
          return { ok: true, sqlite: sqliteOk, localStorage: true, count: normalized.length };
        } catch (err) {
          const quota = isQuotaExceededError(err);
          if (sqliteOk) {
            return { ok: true, sqlite: true, localStorage: false, quotaExceeded: quota, count: normalized.length };
          }
          return { ok: false, quotaExceeded: quota, error: String(err) };
        }
      }

      if (hasNativeKv) {
        return sqliteOk
          ? { ok: true, sqlite: true, localStorage: false, count: normalized.length }
          : { ok: false, quotaExceeded: false, error: '原生 SQLite KV 写入失败' };
      }

      return { ok: false, quotaExceeded: false, error: '当前环境无可用持久化存储' };
    },

    loadTrashItems(ttlDays = 30) {
      const bridge = root.AndroidBridge;
      const hasNativeKvLoad = Boolean(bridge && typeof bridge.dbLoadKeyValue === 'function');
      const ls = getLocalStorageSafe();
      let parsed = null;

      if (hasNativeKvLoad) {
        try {
          const nativeRaw = bridge.dbLoadKeyValue(TRASH_STORAGE_KEY);
          if (typeof nativeRaw === 'string' && nativeRaw.trim().length > 0) {
            parsed = JSON.parse(nativeRaw);
          }
        } catch (_) {
          parsed = null;
        }

        if (!Array.isArray(parsed) && ls) {
          try {
            const localRaw = ls.getItem(TRASH_STORAGE_KEY);
            if (typeof localRaw === 'string' && localRaw.trim().length > 0) {
              const localParsed = JSON.parse(localRaw);
              if (Array.isArray(localParsed)) {
                parsed = localParsed;
                if (typeof bridge.dbSaveKeyValue === 'function') {
                  try {
                    bridge.dbSaveKeyValue(TRASH_STORAGE_KEY, localRaw);
                  } catch (_) {}
                }
              }
            }
          } catch (_) {
            parsed = null;
          }
        }
      } else if (ls) {
        try {
          const localRaw = ls.getItem(TRASH_STORAGE_KEY);
          if (typeof localRaw === 'string' && localRaw.trim().length > 0) {
            parsed = JSON.parse(localRaw);
          }
        } catch (_) {
          parsed = null;
        }
      }

      if (!Array.isArray(parsed)) {
        return [];
      }

      const ttlMs = Number(ttlDays) > 0 ? Number(ttlDays) * 86400000 : 0;
      const now = Date.now();

      return parsed.filter((item) => {
        if (!item || typeof item !== 'object') {
          return false;
        }
        if (ttlMs <= 0 || item.deletedAt == null) {
          return true;
        }
        const ts = Number(item.deletedAt);
        if (!Number.isFinite(ts)) {
          return true;
        }
        return (now - ts) <= ttlMs;
      });
    },

    redactBackupSnapshot(snapshot) {
      return cloneAndRedact(snapshot, new WeakSet());
    },

    async compressImageDataUrl(dataUrl, maxSide = 1280, quality = 0.82) {
      if (typeof dataUrl !== 'string' || !dataUrl.startsWith('data:image/')) {
        return dataUrl;
      }
      if (typeof document === 'undefined' || typeof Image === 'undefined') {
        return dataUrl;
      }

      return new Promise((resolve) => {
        try {
          const img = new Image();
          img.onload = function () {
            try {
              const origW = img.naturalWidth || img.width || 0;
              const origH = img.naturalHeight || img.height || 0;
              if (origW <= 0 || origH <= 0) {
                resolve(dataUrl);
                return;
              }

              const limit = Number(maxSide) > 0 ? Number(maxSide) : 1280;
              const maxDim = Math.max(origW, origH);
              const scale = maxDim > limit ? (limit / maxDim) : 1;
              const targetW = Math.max(1, Math.round(origW * scale));
              const targetH = Math.max(1, Math.round(origH * scale));

              const canvas = document.createElement('canvas');
              canvas.width = targetW;
              canvas.height = targetH;
              const ctx = canvas.getContext('2d');
              if (!ctx) {
                resolve(dataUrl);
                return;
              }

              ctx.drawImage(img, 0, 0, targetW, targetH);
              const q = (Number(quality) > 0 && Number(quality) <= 1) ? Number(quality) : 0.82;
              const compressed = canvas.toDataURL('image/jpeg', q);

              if (!compressed || !compressed.startsWith('data:image/')) {
                resolve(dataUrl);
                return;
              }
              if (scale === 1 && compressed.length >= dataUrl.length) {
                resolve(dataUrl);
                return;
              }
              resolve(compressed);
            } catch (_) {
              resolve(dataUrl);
            }
          };
          img.onerror = function () {
            resolve(dataUrl);
          };
          img.src = dataUrl;
        } catch (_) {
          resolve(dataUrl);
        }
      });
    },

    async saveDraftImage(draftId, dataUrl) {
      const key = String(draftId || '');
      if (!key) {
        return false;
      }
      memoryDraftImages.set(key, dataUrl);
      const db = await openMediaDb();
      if (!db) {
        return true;
      }
      return new Promise((resolve) => {
        try {
          const tx = db.transaction(IDB_STORE_DRAFT_IMAGES, 'readwrite');
          const store = tx.objectStore(IDB_STORE_DRAFT_IMAGES);
          store.put(dataUrl, key);
          tx.oncomplete = function () {
            try { db.close(); } catch (_) {}
            resolve(true);
          };
          tx.onerror = function () {
            try { db.close(); } catch (_) {}
            resolve(true);
          };
        } catch (_) {
          try { db.close(); } catch (_) {}
          resolve(true);
        }
      });
    },

    async getDraftImage(draftId) {
      const key = String(draftId || '');
      if (!key) {
        return null;
      }
      const db = await openMediaDb();
      if (!db) {
        return memoryDraftImages.has(key) ? memoryDraftImages.get(key) : null;
      }
      return new Promise((resolve) => {
        try {
          const tx = db.transaction(IDB_STORE_DRAFT_IMAGES, 'readonly');
          const store = tx.objectStore(IDB_STORE_DRAFT_IMAGES);
          const req = store.get(key);
          req.onsuccess = function () {
            const val = req.result !== undefined ? req.result : (memoryDraftImages.has(key) ? memoryDraftImages.get(key) : null);
            try { db.close(); } catch (_) {}
            resolve(val);
          };
          req.onerror = function () {
            try { db.close(); } catch (_) {}
            resolve(memoryDraftImages.has(key) ? memoryDraftImages.get(key) : null);
          };
        } catch (_) {
          try { db.close(); } catch (_) {}
          resolve(memoryDraftImages.has(key) ? memoryDraftImages.get(key) : null);
        }
      });
    },

    async deleteDraftImage(draftId) {
      const key = String(draftId || '');
      if (!key) {
        return false;
      }
      memoryDraftImages.delete(key);
      const db = await openMediaDb();
      if (!db) {
        return true;
      }
      return new Promise((resolve) => {
        try {
          const tx = db.transaction(IDB_STORE_DRAFT_IMAGES, 'readwrite');
          const store = tx.objectStore(IDB_STORE_DRAFT_IMAGES);
          store.delete(key);
          tx.oncomplete = function () {
            try { db.close(); } catch (_) {}
            resolve(true);
          };
          tx.onerror = function () {
            try { db.close(); } catch (_) {}
            resolve(true);
          };
        } catch (_) {
          try { db.close(); } catch (_) {}
          resolve(true);
        }
      });
    },

    async clearAllDraftImages() {
      memoryDraftImages.clear();
      const db = await openMediaDb();
      if (!db) {
        return true;
      }
      return new Promise((resolve) => {
        try {
          const tx = db.transaction(IDB_STORE_DRAFT_IMAGES, 'readwrite');
          const store = tx.objectStore(IDB_STORE_DRAFT_IMAGES);
          store.clear();
          tx.oncomplete = function () {
            try { db.close(); } catch (_) {}
            resolve(true);
          };
          tx.onerror = function () {
            try { db.close(); } catch (_) {}
            resolve(true);
          };
        } catch (_) {
          try { db.close(); } catch (_) {}
          resolve(true);
        }
      });
    },

    async computeSha256Hex(input) {
      let bytes;
      if (typeof input === 'string') {
        bytes = encodeUtf8(input);
      } else {
        bytes = toUint8Array(input);
      }
      if (!bytes) {
        throw new Error('computeSha256Hex 输入必须是字符串或二进制字节数组');
      }
      const webCrypto = getWebCrypto();
      const digest = await webCrypto.subtle.digest('SHA-256', bytes);
      const view = new Uint8Array(digest);
      let hex = '';
      for (let i = 0; i < view.length; i++) {
        hex += view[i].toString(16).padStart(2, '0');
      }
      return hex;
    },

    findFuzzyDuplicate(candidate, allMonthlyData) {
      if (!candidate || typeof candidate !== 'object' || !allMonthlyData) {
        return null;
      }
      const candMerchant = normalizeMerchantForDedup(
        candidate.merchant || candidate.name || candidate.merchant_raw
      );
      if (!candMerchant) {
        return null;
      }

      const candRawAmt = (candidate.amount != null && candidate.amount !== '')
        ? candidate.amount
        : (Number(candidate.amountInCents || 0) / 100);
      const candCents = Math.abs(MoneyMath.toCents(candRawAmt));
      const candTimeMs = parseTimestampMs(candidate);
      if (!Number.isFinite(candTimeMs)) {
        return null;
      }

      const activeList = collectActiveTransactionsFromMonthly(allMonthlyData);
      const ONE_DAY_MS = 86400000;

      for (let i = 0; i < activeList.length; i++) {
        const tx = activeList[i];
        if (!tx || typeof tx !== 'object') {
          continue;
        }
        if (candidate.id && tx.id && candidate.id === tx.id) {
          continue;
        }
        const txMerchant = normalizeMerchantForDedup(
          tx.merchant || tx.name || tx.merchant_raw
        );
        if (txMerchant !== candMerchant) {
          continue;
        }

        const txRawAmt = (tx.amount != null && tx.amount !== '')
          ? tx.amount
          : (Number(tx.amountInCents || 0) / 100);
        const txCents = Math.abs(MoneyMath.toCents(txRawAmt));
        if (txCents !== candCents) {
          continue;
        }

        const txTimeMs = parseTimestampMs(tx);
        if (!Number.isFinite(txTimeMs)) {
          continue;
        }
        if (Math.abs(txTimeMs - candTimeMs) <= ONE_DAY_MS) {
          return tx;
        }
      }

      return null;
    }
  };

  root.escapeHtml = escapeHtml;
  root.MoneyMath = MoneyMath;
  root.SwbkCrypto = SwbkCrypto;
  root.CsvExporter = CsvExporter;
  root.LedgerStorage = LedgerStorage;

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      escapeHtml,
      MoneyMath,
      SwbkCrypto,
      CsvExporter,
      LedgerStorage
    };
  }
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
