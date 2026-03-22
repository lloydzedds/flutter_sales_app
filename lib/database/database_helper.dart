import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const _databaseName = 'sales.db';
  static const _databaseVersion = 7;
  static const _groupKeyExpr =
      "COALESCE(sales.sale_group_id, 'legacy-' || CAST(sales.id AS TEXT))";

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_databaseName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        cost_price REAL NOT NULL,
        selling_price REAL NOT NULL,
        stock INTEGER NOT NULL,
        photo_bytes BLOB
      )
    ''');

    await db.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT,
        units INTEGER NOT NULL,
        discount REAL NOT NULL,
        total REAL NOT NULL,
        profit REAL NOT NULL,
        date TEXT NOT NULL,
        cost_price REAL,
        selling_price REAL,
        sale_group_id TEXT,
        customer_id INTEGER,
        customer_name TEXT,
        customer_phone TEXT,
        bill_number TEXT,
        payment_status TEXT,
        payment_method TEXT,
        amount_paid REAL,
        due_amount REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        created_at TEXT,
        updated_at TEXT,
        last_purchase_date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_returns(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_group_id TEXT,
        sale_group_key TEXT NOT NULL,
        sale_id INTEGER NOT NULL,
        bill_number TEXT,
        customer_id INTEGER,
        customer_name TEXT,
        customer_phone TEXT,
        product_id INTEGER,
        product_name TEXT,
        units INTEGER NOT NULL,
        discount REAL NOT NULL,
        refund_amount REAL NOT NULL,
        profit_adjustment REAL NOT NULL,
        cost_price REAL,
        selling_price REAL,
        date TEXT NOT NULL,
        reason TEXT,
        restocked INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings(
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _ensureSalesColumns(db, {
        'cost_price': 'ALTER TABLE sales ADD COLUMN cost_price REAL',
        'selling_price': 'ALTER TABLE sales ADD COLUMN selling_price REAL',
      });
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings(
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS customers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          created_at TEXT,
          updated_at TEXT,
          last_purchase_date TEXT
        )
      ''');

      await _ensureSalesColumns(db, {
        'product_name': 'ALTER TABLE sales ADD COLUMN product_name TEXT',
        'sale_group_id': 'ALTER TABLE sales ADD COLUMN sale_group_id TEXT',
        'customer_id': 'ALTER TABLE sales ADD COLUMN customer_id INTEGER',
        'customer_name': 'ALTER TABLE sales ADD COLUMN customer_name TEXT',
        'customer_phone': 'ALTER TABLE sales ADD COLUMN customer_phone TEXT',
        'bill_number': 'ALTER TABLE sales ADD COLUMN bill_number TEXT',
      });
    }

    if (oldVersion < 5) {
      await _ensureProductColumns(db, {
        'photo_bytes': 'ALTER TABLE products ADD COLUMN photo_bytes BLOB',
      });
    }

    if (oldVersion < 6) {
      await _ensureSalesColumns(db, {
        'payment_status': 'ALTER TABLE sales ADD COLUMN payment_status TEXT',
        'payment_method': 'ALTER TABLE sales ADD COLUMN payment_method TEXT',
        'amount_paid': 'ALTER TABLE sales ADD COLUMN amount_paid REAL',
        'due_amount': 'ALTER TABLE sales ADD COLUMN due_amount REAL',
      });
    }

    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sale_returns(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          return_group_id TEXT,
          sale_group_key TEXT NOT NULL,
          sale_id INTEGER NOT NULL,
          bill_number TEXT,
          customer_id INTEGER,
          customer_name TEXT,
          customer_phone TEXT,
          product_id INTEGER,
          product_name TEXT,
          units INTEGER NOT NULL,
          discount REAL NOT NULL,
          refund_amount REAL NOT NULL,
          profit_adjustment REAL NOT NULL,
          cost_price REAL,
          selling_price REAL,
          date TEXT NOT NULL,
          reason TEXT,
          restocked INTEGER NOT NULL DEFAULT 1
        )
      ''');
    }
  }

  Future<void> _ensureSalesColumns(
    Database db,
    Map<String, String> columnStatements,
  ) async {
    final columns = await db.rawQuery("PRAGMA table_info(sales)");
    final names = columns
        .map((column) => column['name'] as String?)
        .whereType<String>()
        .toSet();

    for (final entry in columnStatements.entries) {
      if (!names.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }
  }

  Future<void> _ensureProductColumns(
    Database db,
    Map<String, String> columnStatements,
  ) async {
    final columns = await db.rawQuery("PRAGMA table_info(products)");
    final names = columns
        .map((column) => column['name'] as String?)
        .whereType<String>()
        .toSet();

    for (final entry in columnStatements.entries) {
      if (!names.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _trim(String? value) => value?.trim() ?? '';

  String _nowStamp() => DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

  Map<String, dynamic> _resolvePaymentFields({
    required List<Map<String, dynamic>> items,
    String? paymentStatus,
    String? paymentMethod,
    double? amountPaid,
  }) {
    final total = items.fold<double>(
      0,
      (sum, item) => sum + _asDouble(item['total']),
    );
    final requestedStatus = _trim(paymentStatus).toLowerCase();

    if (total <= 0) {
      return {
        'payment_status': 'paid',
        'payment_method': _trim(paymentMethod).isEmpty
            ? 'Cash'
            : _trim(paymentMethod),
        'amount_paid': 0.0,
        'due_amount': 0.0,
      };
    }

    late final String normalizedStatus;
    late final double normalizedAmountPaid;

    switch (requestedStatus) {
      case 'partial':
      case 'partially_paid':
        normalizedStatus = 'partial';
        normalizedAmountPaid = _asDouble(amountPaid);
        if (normalizedAmountPaid <= 0 || normalizedAmountPaid >= total) {
          throw Exception(
            'Enter an amount received that is more than 0 and less than the total',
          );
        }
        break;
      case 'unpaid':
        normalizedStatus = 'unpaid';
        normalizedAmountPaid = 0;
        break;
      case 'paid':
      default:
        normalizedStatus = 'paid';
        normalizedAmountPaid = total;
        break;
    }

    final dueAmount = total > normalizedAmountPaid
        ? total - normalizedAmountPaid
        : 0.0;
    final normalizedMethod = _trim(paymentMethod).isEmpty
        ? normalizedStatus == 'unpaid'
              ? 'Credit'
              : 'Cash'
        : _trim(paymentMethod);

    return {
      'payment_status': normalizedStatus,
      'payment_method': normalizedMethod,
      'amount_paid': normalizedAmountPaid,
      'due_amount': dueAmount,
    };
  }

  Future<int> insertProduct(Map<String, dynamic> row) async {
    final db = await instance.database;
    return db.insert('products', row);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await instance.database;
    return db.query('products', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<void> saveAppSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getAppSetting(String key) async {
    final db = await instance.database;
    final result = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first['value']?.toString();
  }

  Future<Map<String, String>> getStoreDetails() async {
    const keys = [
      'store_name',
      'store_owner',
      'store_phone',
      'store_email',
      'store_address',
      'store_tax_id',
      'invoice_prefix',
      'invoice_note',
    ];

    final details = <String, String>{};
    for (final key in keys) {
      details[key] = await getAppSetting(key) ?? '';
    }
    return details;
  }

  Future<void> saveStoreDetails(Map<String, String> details) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      for (final entry in details.entries) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> insertSale(Map<String, dynamic> row) async {
    final db = await instance.database;
    return db.insert('sales', row);
  }

  Future<void> updateStock(int productId, int newStock) async {
    final db = await instance.database;
    await db.update(
      'products',
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> updateProduct({
    required int productId,
    required String name,
    required double costPrice,
    required double sellingPrice,
    required int stock,
    Uint8List? photoBytes,
  }) async {
    final db = await instance.database;
    await db.update(
      'products',
      {
        'name': name,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'stock': stock,
        'photo_bytes': photoBytes,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<Map<String, dynamic>?> findProduct(String name, double price) async {
    final db = await instance.database;

    final result = await db.query(
      'products',
      where: 'name = ? AND selling_price = ?',
      whereArgs: [name, price],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first;
  }

  Future<List<Map<String, dynamic>>> findByName(String name) async {
    final db = await instance.database;
    return db.query(
      'products',
      where: 'name LIKE ?',
      whereArgs: ['$name%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<void> deleteProduct(int id) async {
    final db = await instance.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> _upsertCustomerTxn(
    Transaction txn, {
    required String name,
    required String phone,
    required String purchaseDate,
  }) async {
    final cleanName = _trim(name);
    final cleanPhone = _trim(phone);

    if (cleanName.isEmpty && cleanPhone.isEmpty) {
      return null;
    }

    Map<String, dynamic>? existing;
    if (cleanPhone.isNotEmpty) {
      final byPhone = await txn.query(
        'customers',
        where: 'phone = ?',
        whereArgs: [cleanPhone],
        limit: 1,
      );
      if (byPhone.isNotEmpty) {
        existing = byPhone.first;
      }
    }

    if (existing == null && cleanName.isNotEmpty) {
      final byName = await txn.query(
        'customers',
        where: 'LOWER(name) = LOWER(?)',
        whereArgs: [cleanName],
        limit: 1,
      );
      if (byName.isNotEmpty) {
        existing = byName.first;
      }
    }

    final payload = <String, dynamic>{
      'name': cleanName.isEmpty ? (existing?['name'] ?? 'Customer') : cleanName,
      'phone': cleanPhone.isEmpty ? null : cleanPhone,
      'updated_at': purchaseDate,
      'last_purchase_date': purchaseDate,
    };

    if (existing != null) {
      await txn.update(
        'customers',
        payload,
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
      return {'id': existing['id'], ...payload};
    }

    payload['created_at'] = purchaseDate;
    final id = await txn.insert('customers', payload);
    return {'id': id, ...payload};
  }

  Future<String> _buildBillNumberTxn(Transaction txn, String saleDate) async {
    final prefixResult = await txn.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['invoice_prefix'],
      limit: 1,
    );
    final prefix = _trim(
      prefixResult.isEmpty ? null : prefixResult.first['value']?.toString(),
    );
    final effectivePrefix = prefix.isEmpty ? 'INV' : prefix;

    final parsedDate = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).parseStrict(saleDate, true).toLocal();
    final timeStamp = DateFormat('yyyyMMdd-HHmmss').format(parsedDate);
    return '$effectivePrefix-$timeStamp';
  }

  Future<List<Map<String, dynamic>>> _loadSaleRowsForGroupKeyTxn(
    Transaction txn,
    String groupKey,
  ) async {
    final groupedRows = await txn.query(
      'sales',
      where: 'sale_group_id = ?',
      whereArgs: [groupKey],
      orderBy: 'id ASC',
    );

    if (groupedRows.isNotEmpty) {
      return groupedRows;
    }

    if (groupKey.startsWith('legacy-')) {
      final legacyId = int.tryParse(groupKey.substring('legacy-'.length));
      if (legacyId != null) {
        return txn.query(
          'sales',
          where: 'id = ?',
          whereArgs: [legacyId],
          orderBy: 'id ASC',
        );
      }
    }

    return const [];
  }

  Future<void> _restoreStockForRowsTxn(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    final restoredUnits = <int, int>{};
    for (final row in rows) {
      final productId = _asInt(row['product_id']);
      final units = _asInt(row['units']);
      restoredUnits[productId] = (restoredUnits[productId] ?? 0) + units;
    }

    for (final entry in restoredUnits.entries) {
      final product = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (product.isEmpty) continue;

      final currentStock = _asInt(product.first['stock']);
      await txn.update(
        'products',
        {'stock': currentStock + entry.value},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  Future<void> _deductStockForItemsTxn(
    Transaction txn,
    List<Map<String, dynamic>> items,
  ) async {
    final requestedUnits = <int, int>{};
    for (final item in items) {
      final productId = _asInt(item['product_id']);
      final units = _asInt(item['units']);
      requestedUnits[productId] = (requestedUnits[productId] ?? 0) + units;
    }

    for (final entry in requestedUnits.entries) {
      final product = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );

      if (product.isEmpty) {
        throw Exception('Selected product not found');
      }

      final currentStock = _asInt(product.first['stock']);
      if (entry.value > currentStock) {
        throw Exception(
          'Not enough stock for ${product.first['name']?.toString() ?? 'product'}',
        );
      }

      await txn.update(
        'products',
        {'stock': currentStock - entry.value},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  Future<Map<int, int>> _returnedUnitsBySaleIdTxn(
    Transaction txn,
    String groupKey,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT sale_id, SUM(units) AS returned_units
      FROM sale_returns
      WHERE sale_group_key = ?
      GROUP BY sale_id
    ''',
      [groupKey],
    );

    final returnedUnits = <int, int>{};
    for (final row in rows) {
      returnedUnits[_asInt(row['sale_id'])] = _asInt(row['returned_units']);
    }
    return returnedUnits;
  }

  Future<bool> hasReturnsForGroupKey(String groupKey) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM sale_returns
      WHERE sale_group_key = ?
      LIMIT 1
    ''',
      [groupKey],
    );
    return _asInt(rows.first['count']) > 0;
  }

  Future<void> recordSaleReturn({
    required String groupKey,
    required List<Map<String, dynamic>> items,
    bool restock = true,
    String? reason,
  }) async {
    final db = await instance.database;
    final returnDate = _nowStamp();
    final returnGroupId = 'return-${DateTime.now().microsecondsSinceEpoch}';
    final cleanReason = _trim(reason);

    await db.transaction((txn) async {
      final saleRows = await _loadSaleRowsForGroupKeyTxn(txn, groupKey);
      if (saleRows.isEmpty) {
        throw Exception('Sale not found');
      }

      if (items.isEmpty) {
        throw Exception('Select at least one product to return');
      }

      final saleRowsById = <int, Map<String, dynamic>>{};
      for (final row in saleRows) {
        saleRowsById[_asInt(row['id'])] = row;
      }

      final returnedUnitsBySaleId = await _returnedUnitsBySaleIdTxn(
        txn,
        groupKey,
      );
      final stockToRestore = <int, int>{};

      for (final item in items) {
        final saleId = _asInt(item['sale_id']);
        final returnUnits = _asInt(item['units']);
        if (returnUnits <= 0) {
          continue;
        }

        final saleRow = saleRowsById[saleId];
        if (saleRow == null) {
          throw Exception('The selected sale item no longer exists');
        }

        final soldUnits = _asInt(saleRow['units']);
        final alreadyReturned = returnedUnitsBySaleId[saleId] ?? 0;
        final remainingUnits = soldUnits - alreadyReturned;
        final productName =
            _trim(saleRow['product_name']?.toString()).isNotEmpty
            ? _trim(saleRow['product_name']?.toString())
            : 'Product';

        if (returnUnits > remainingUnits) {
          throw Exception(
            'You can return only $remainingUnits unit(s) of $productName',
          );
        }

        final productId = _asInt(saleRow['product_id']);
        final discount = _asDouble(saleRow['discount']);
        final sellingPrice = _asDouble(saleRow['selling_price']);
        final costPrice = _asDouble(saleRow['cost_price']);
        final soldPrice = sellingPrice - discount;
        final refundAmount = soldPrice * returnUnits;
        final originalProfitPortion = (soldPrice - costPrice) * returnUnits;
        final profitAdjustment = restock ? originalProfitPortion : refundAmount;

        await txn.insert('sale_returns', {
          'return_group_id': returnGroupId,
          'sale_group_key': groupKey,
          'sale_id': saleId,
          'bill_number': saleRow['bill_number']?.toString(),
          'customer_id': saleRow['customer_id'],
          'customer_name': saleRow['customer_name']?.toString(),
          'customer_phone': saleRow['customer_phone']?.toString(),
          'product_id': productId,
          'product_name': saleRow['product_name']?.toString(),
          'units': returnUnits,
          'discount': discount,
          'refund_amount': refundAmount,
          'profit_adjustment': profitAdjustment,
          'cost_price': costPrice,
          'selling_price': sellingPrice,
          'date': returnDate,
          'reason': cleanReason.isEmpty ? null : cleanReason,
          'restocked': restock ? 1 : 0,
        });

        if (restock) {
          stockToRestore[productId] =
              (stockToRestore[productId] ?? 0) + returnUnits;
        }
      }

      if (stockToRestore.isEmpty || !restock) {
        return;
      }

      for (final entry in stockToRestore.entries) {
        final product = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );

        if (product.isEmpty) {
          throw Exception(
            'The original product was deleted, so stock cannot be restored',
          );
        }

        final currentStock = _asInt(product.first['stock']);
        await txn.update(
          'products',
          {'stock': currentStock + entry.value},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
    });
  }

  Future<String> createSaleOrder({
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
    String? paymentStatus,
    String? paymentMethod,
    double? amountPaid,
  }) async {
    final db = await instance.database;
    final saleDate = _nowStamp();
    final groupKey = 'sale-${DateTime.now().microsecondsSinceEpoch}';

    await db.transaction((txn) async {
      if (items.isEmpty) {
        throw Exception('Add at least one product to the sale');
      }

      final customer = await _upsertCustomerTxn(
        txn,
        name: customerName ?? '',
        phone: customerPhone ?? '',
        purchaseDate: saleDate,
      );
      final billNumber = await _buildBillNumberTxn(txn, saleDate);
      final paymentFields = _resolvePaymentFields(
        items: items,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        amountPaid: amountPaid,
      );

      await _deductStockForItemsTxn(txn, items);

      for (final item in items) {
        await txn.insert('sales', {
          'product_id': _asInt(item['product_id']),
          'product_name': item['product_name']?.toString(),
          'units': _asInt(item['units']),
          'discount': _asDouble(item['discount']),
          'total': _asDouble(item['total']),
          'profit': _asDouble(item['profit']),
          'date': saleDate,
          'cost_price': _asDouble(item['cost_price']),
          'selling_price': _asDouble(item['selling_price']),
          'sale_group_id': groupKey,
          'customer_id': customer?['id'],
          'customer_name': _trim(customerName).isEmpty
              ? null
              : _trim(customerName),
          'customer_phone': _trim(customerPhone).isEmpty
              ? null
              : _trim(customerPhone),
          'bill_number': billNumber,
          'payment_status': paymentFields['payment_status'],
          'payment_method': paymentFields['payment_method'],
          'amount_paid': paymentFields['amount_paid'],
          'due_amount': paymentFields['due_amount'],
        });
      }
    });

    return groupKey;
  }

  Future<void> updateSaleOrder({
    required String groupKey,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
    String? paymentStatus,
    String? paymentMethod,
    double? amountPaid,
  }) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      final hasReturns = await _returnedUnitsBySaleIdTxn(txn, groupKey);
      if (hasReturns.isNotEmpty) {
        throw Exception(
          'This sale already has returns recorded, so editing is disabled.',
        );
      }

      final existingRows = await _loadSaleRowsForGroupKeyTxn(txn, groupKey);
      if (existingRows.isEmpty) {
        throw Exception('Sale not found');
      }

      final preservedDate =
          existingRows.first['date']?.toString() ?? _nowStamp();
      final preservedBillNumber = _trim(
        existingRows.first['bill_number']?.toString(),
      );

      await _restoreStockForRowsTxn(txn, existingRows);

      final customer = await _upsertCustomerTxn(
        txn,
        name: customerName ?? '',
        phone: customerPhone ?? '',
        purchaseDate: preservedDate,
      );
      final paymentFields = _resolvePaymentFields(
        items: items,
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
        amountPaid: amountPaid,
      );

      if (_trim(existingRows.first['sale_group_id']?.toString()).isNotEmpty) {
        await txn.delete(
          'sales',
          where: 'sale_group_id = ?',
          whereArgs: [groupKey],
        );
      } else {
        await txn.delete(
          'sales',
          where: 'id = ?',
          whereArgs: [existingRows.first['id']],
        );
      }

      await _deductStockForItemsTxn(txn, items);

      final nextBillNumber = preservedBillNumber.isEmpty
          ? await _buildBillNumberTxn(txn, preservedDate)
          : preservedBillNumber;

      for (final item in items) {
        await txn.insert('sales', {
          'product_id': _asInt(item['product_id']),
          'product_name': item['product_name']?.toString(),
          'units': _asInt(item['units']),
          'discount': _asDouble(item['discount']),
          'total': _asDouble(item['total']),
          'profit': _asDouble(item['profit']),
          'date': preservedDate,
          'cost_price': _asDouble(item['cost_price']),
          'selling_price': _asDouble(item['selling_price']),
          'sale_group_id': groupKey,
          'customer_id': customer?['id'],
          'customer_name': _trim(customerName).isEmpty
              ? null
              : _trim(customerName),
          'customer_phone': _trim(customerPhone).isEmpty
              ? null
              : _trim(customerPhone),
          'bill_number': nextBillNumber,
          'payment_status': paymentFields['payment_status'],
          'payment_method': paymentFields['payment_method'],
          'amount_paid': paymentFields['amount_paid'],
          'due_amount': paymentFields['due_amount'],
        });
      }
    });
  }

  Future<void> updateSale({
    required int saleId,
    required int productId,
    required int units,
    required double discount,
    required double total,
    required double profit,
    required double costPrice,
    required double sellingPrice,
  }) async {
    final groupKey = 'legacy-$saleId';
    await updateSaleOrder(
      groupKey: groupKey,
      items: [
        {
          'product_id': productId,
          'product_name': '',
          'units': units,
          'discount': discount,
          'total': total,
          'profit': profit,
          'cost_price': costPrice,
          'selling_price': sellingPrice,
        },
      ],
    );
  }

  Future<void> deleteSale(int saleId) async {
    await deleteSaleOrder('legacy-$saleId');
  }

  Future<void> deleteSaleOrder(String groupKey) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      final hasReturns = await _returnedUnitsBySaleIdTxn(txn, groupKey);
      if (hasReturns.isNotEmpty) {
        throw Exception(
          'This sale already has returns recorded, so deleting is disabled.',
        );
      }

      final existingRows = await _loadSaleRowsForGroupKeyTxn(txn, groupKey);
      if (existingRows.isEmpty) return;

      await _restoreStockForRowsTxn(txn, existingRows);

      if (_trim(existingRows.first['sale_group_id']?.toString()).isNotEmpty) {
        await txn.delete(
          'sales',
          where: 'sale_group_id = ?',
          whereArgs: [groupKey],
        );
      } else {
        await txn.delete(
          'sales',
          where: 'id = ?',
          whereArgs: [existingRows.first['id']],
        );
      }
    });
  }

  String get _grossLineProfitExpr => '''
      CASE
        WHEN COALESCE(sales.cost_price, products.cost_price) IS NOT NULL
          AND COALESCE(sales.selling_price, products.selling_price) IS NOT NULL
        THEN (
          (COALESCE(sales.selling_price, products.selling_price) - sales.discount) -
          COALESCE(sales.cost_price, products.cost_price)
        ) * sales.units
        ELSE sales.profit
      END
    ''';

  String get _lineReturnJoin => '''
      LEFT JOIN (
        SELECT
          sale_id,
          SUM(units) AS returned_units,
          SUM(refund_amount) AS returned_total,
          SUM(profit_adjustment) AS returned_profit_adjustment
        FROM sale_returns
        GROUP BY sale_id
      ) return_line_agg
        ON return_line_agg.sale_id = sales.id
    ''';

  String get _orderReturnJoin =>
      '''
      LEFT JOIN (
        SELECT
          sale_group_key,
          COUNT(DISTINCT return_group_id) AS return_count,
          SUM(units) AS returned_units,
          SUM(refund_amount) AS returned_total,
          SUM(profit_adjustment) AS returned_profit_adjustment,
          MAX(date) AS last_return_date
        FROM sale_returns
        GROUP BY sale_group_key
      ) return_order_agg
        ON return_order_agg.sale_group_key = $_groupKeyExpr
    ''';

  String get _salesLineItemSelect =>
      '''
      SELECT
        sales.id,
        $_groupKeyExpr AS group_key,
        sales.sale_group_id,
        sales.bill_number,
        sales.customer_id,
        COALESCE(NULLIF(TRIM(sales.customer_name), ''), customers.name, '') AS customer_name,
        COALESCE(NULLIF(TRIM(sales.customer_phone), ''), customers.phone, '') AS customer_phone,
        sales.product_id,
        COALESCE(NULLIF(TRIM(sales.product_name), ''), products.name, 'Deleted Product') AS product_name,
        COALESCE(NULLIF(TRIM(sales.product_name), ''), products.name, 'Deleted Product') AS name,
        sales.units,
        COALESCE(return_line_agg.returned_units, 0) AS returned_units,
        CASE
          WHEN sales.units > COALESCE(return_line_agg.returned_units, 0)
          THEN sales.units - COALESCE(return_line_agg.returned_units, 0)
          ELSE 0
        END AS net_units,
        sales.discount,
        sales.total AS gross_total,
        CASE
          WHEN sales.total > COALESCE(return_line_agg.returned_total, 0)
          THEN sales.total - COALESCE(return_line_agg.returned_total, 0)
          ELSE 0
        END AS total,
        COALESCE(return_line_agg.returned_total, 0) AS returned_total,
        sales.date,
        COALESCE(sales.cost_price, products.cost_price) AS cost_price,
        COALESCE(sales.selling_price, products.selling_price) AS selling_price,
        CASE
          WHEN COALESCE(sales.selling_price, products.selling_price) IS NOT NULL
          THEN COALESCE(sales.selling_price, products.selling_price) - sales.discount
          ELSE NULL
        END AS sold_price,
        COALESCE(NULLIF(TRIM(sales.payment_status), ''), 'paid') AS payment_status,
        COALESCE(NULLIF(TRIM(sales.payment_method), ''), 'Cash') AS payment_method,
        COALESCE(
          sales.amount_paid,
          (
            SELECT SUM(s2.total)
            FROM sales s2
            WHERE COALESCE(
                    s2.sale_group_id,
                    'legacy-' || CAST(s2.id AS TEXT)
                  ) = $_groupKeyExpr
          )
        ) AS amount_paid,
        COALESCE(sales.due_amount, 0) AS due_amount,
        $_grossLineProfitExpr AS gross_profit,
        $_grossLineProfitExpr - COALESCE(return_line_agg.returned_profit_adjustment, 0) AS profit,
        COALESCE(return_line_agg.returned_profit_adjustment, 0) AS returned_profit_adjustment
      FROM sales
      LEFT JOIN products
        ON sales.product_id = products.id
      LEFT JOIN customers
        ON sales.customer_id = customers.id
      $_lineReturnJoin
    ''';

  Future<List<Map<String, dynamic>>> getSalesWithProduct() async {
    final db = await instance.database;
    return db.rawQuery('''
      $_salesLineItemSelect
      ORDER BY sales.date DESC, sales.id DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getSalesByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await instance.database;
    return db.rawQuery(
      '''
      $_salesLineItemSelect
      WHERE sales.date BETWEEN ? AND ?
      ORDER BY sales.date DESC, sales.id DESC
    ''',
      [startDate, endDate],
    );
  }

  Future<List<Map<String, dynamic>>> getSaleItemsForExport({
    String? startDate,
    String? endDate,
  }) async {
    final db = await instance.database;
    final whereClause = startDate != null && endDate != null
        ? 'WHERE sales.date BETWEEN ? AND ?'
        : '';
    final args = startDate != null && endDate != null
        ? [startDate, endDate]
        : const <Object?>[];

    return db.rawQuery('''
      $_salesLineItemSelect
      $whereClause
      ORDER BY sales.date DESC, sales.id DESC
    ''', args);
  }

  String get _saleOrderSelect =>
      '''
      SELECT
        MIN(sales.id) AS id,
        $_groupKeyExpr AS group_key,
        MAX(COALESCE(NULLIF(TRIM(sales.bill_number), ''), '')) AS bill_number,
        MAX(sales.customer_id) AS customer_id,
        COALESCE(
          NULLIF(TRIM(MAX(sales.customer_name)), ''),
          MAX(customers.name),
          'Walk-in Customer'
        ) AS customer_name,
        COALESCE(
          NULLIF(TRIM(MAX(sales.customer_phone)), ''),
          MAX(customers.phone),
          ''
        ) AS customer_phone,
        MAX(COALESCE(return_order_agg.return_count, 0)) AS return_count,
        MAX(COALESCE(return_order_agg.last_return_date, '')) AS last_return_date,
        COALESCE(NULLIF(TRIM(MAX(sales.payment_status)), ''), 'paid') AS payment_status,
        COALESCE(NULLIF(TRIM(MAX(sales.payment_method)), ''), 'Cash') AS payment_method,
        COALESCE(MAX(sales.amount_paid), SUM(sales.total)) AS amount_paid,
        COALESCE(MAX(sales.due_amount), 0) AS due_amount,
        MAX(sales.date) AS date,
        COUNT(*) AS item_count,
        SUM(sales.units) AS gross_units,
        CASE
          WHEN SUM(sales.units) > MAX(COALESCE(return_order_agg.returned_units, 0))
          THEN SUM(sales.units) - MAX(COALESCE(return_order_agg.returned_units, 0))
          ELSE 0
        END AS total_units,
        SUM(sales.total) AS gross_total,
        MAX(COALESCE(return_order_agg.returned_total, 0)) AS returned_total,
        CASE
          WHEN SUM(sales.total) > MAX(COALESCE(return_order_agg.returned_total, 0))
          THEN SUM(sales.total) - MAX(COALESCE(return_order_agg.returned_total, 0))
          ELSE 0
        END AS total,
        SUM($_grossLineProfitExpr) AS gross_profit,
        MAX(COALESCE(return_order_agg.returned_profit_adjustment, 0)) AS returned_profit_adjustment,
        SUM($_grossLineProfitExpr) -
            MAX(COALESCE(return_order_agg.returned_profit_adjustment, 0)) AS profit,
        GROUP_CONCAT(
          COALESCE(NULLIF(TRIM(sales.product_name), ''), products.name, 'Deleted Product')
        ) AS product_names
      FROM sales
      LEFT JOIN products
        ON sales.product_id = products.id
      LEFT JOIN customers
        ON sales.customer_id = customers.id
      $_orderReturnJoin
    ''';

  Future<List<Map<String, dynamic>>> getSaleOrders() async {
    final db = await instance.database;
    return db.rawQuery('''
      $_saleOrderSelect
      GROUP BY $_groupKeyExpr
      ORDER BY MAX(sales.date) DESC, MIN(sales.id) DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getSaleOrdersByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await instance.database;
    return db.rawQuery(
      '''
      $_saleOrderSelect
      WHERE sales.date BETWEEN ? AND ?
      GROUP BY $_groupKeyExpr
      ORDER BY MAX(sales.date) DESC, MIN(sales.id) DESC
    ''',
      [startDate, endDate],
    );
  }

  Future<Map<String, dynamic>?> getSaleOrderByGroupKey(String groupKey) async {
    final db = await instance.database;
    final groupedRows = await db.rawQuery(
      '''
      $_saleOrderSelect
      WHERE sales.sale_group_id = ?
      GROUP BY $_groupKeyExpr
      LIMIT 1
    ''',
      [groupKey],
    );

    if (groupedRows.isNotEmpty) {
      return groupedRows.first;
    }

    if (groupKey.startsWith('legacy-')) {
      final legacyId = int.tryParse(groupKey.substring('legacy-'.length));
      if (legacyId != null) {
        final legacyRows = await db.rawQuery(
          '''
          $_saleOrderSelect
          WHERE sales.id = ?
          GROUP BY $_groupKeyExpr
          LIMIT 1
        ''',
          [legacyId],
        );
        if (legacyRows.isNotEmpty) {
          return legacyRows.first;
        }
      }
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> getSaleItemsForGroupKey(
    String groupKey,
  ) async {
    final db = await instance.database;
    final groupedRows = await db.rawQuery(
      '''
      $_salesLineItemSelect
      WHERE sales.sale_group_id = ?
      ORDER BY sales.id ASC
    ''',
      [groupKey],
    );

    if (groupedRows.isNotEmpty) {
      return groupedRows;
    }

    if (groupKey.startsWith('legacy-')) {
      final legacyId = int.tryParse(groupKey.substring('legacy-'.length));
      if (legacyId != null) {
        return db.rawQuery(
          '''
          $_salesLineItemSelect
          WHERE sales.id = ?
          ORDER BY sales.id ASC
        ''',
          [legacyId],
        );
      }
    }

    return const [];
  }

  Future<List<Map<String, dynamic>>> getSaleReturnsForGroupKey(
    String groupKey,
  ) async {
    final db = await instance.database;
    return db.rawQuery(
      '''
      SELECT
        sale_returns.id,
        sale_returns.return_group_id,
        sale_returns.sale_group_key,
        sale_returns.sale_id,
        sale_returns.bill_number,
        sale_returns.customer_id,
        COALESCE(NULLIF(TRIM(sale_returns.customer_name), ''), 'Walk-in Customer') AS customer_name,
        COALESCE(NULLIF(TRIM(sale_returns.customer_phone), ''), '') AS customer_phone,
        sale_returns.product_id,
        COALESCE(
          NULLIF(TRIM(sale_returns.product_name), ''),
          products.name,
          'Deleted Product'
        ) AS product_name,
        sale_returns.units,
        sale_returns.discount,
        sale_returns.refund_amount,
        sale_returns.profit_adjustment,
        sale_returns.cost_price,
        sale_returns.selling_price,
        CASE
          WHEN sale_returns.selling_price IS NOT NULL
          THEN sale_returns.selling_price - sale_returns.discount
          ELSE NULL
        END AS sold_price,
        sale_returns.date,
        COALESCE(NULLIF(TRIM(sale_returns.reason), ''), 'No reason added') AS reason,
        sale_returns.restocked
      FROM sale_returns
      LEFT JOIN products
        ON sale_returns.product_id = products.id
      WHERE sale_returns.sale_group_key = ?
      ORDER BY sale_returns.date DESC, sale_returns.id DESC
    ''',
      [groupKey],
    );
  }

  Future<Map<String, dynamic>> getTodaySummary() async {
    final db = await instance.database;
    final today = DateTime.now();
    final todayString =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final result = await db.rawQuery(
      '''
      SELECT
        COUNT(DISTINCT $_groupKeyExpr) AS total_sales,
        SUM(
          CASE
            WHEN sales.total > COALESCE(return_line_agg.returned_total, 0)
            THEN sales.total - COALESCE(return_line_agg.returned_total, 0)
            ELSE 0
          END
        ) AS total_revenue,
        SUM(
          $_grossLineProfitExpr - COALESCE(return_line_agg.returned_profit_adjustment, 0)
        ) AS total_profit
      FROM sales
      LEFT JOIN products
        ON sales.product_id = products.id
      $_lineReturnJoin
      WHERE sales.date LIKE ?
    ''',
      ['$todayString%'],
    );

    return result.first;
  }

  Future<List<Map<String, dynamic>>> getDailyRevenue() async {
    final db = await instance.database;
    return db.rawQuery('''
      SELECT
        SUBSTR(date, 1, 10) AS day,
        SUM(
          CASE
            WHEN sales.total > COALESCE(return_line_agg.returned_total, 0)
            THEN sales.total - COALESCE(return_line_agg.returned_total, 0)
            ELSE 0
          END
        ) AS revenue
      FROM sales
      $_lineReturnJoin
      GROUP BY day
      ORDER BY day
    ''');
  }

  Future<List<Map<String, dynamic>>> getCustomers({String search = ''}) async {
    final db = await instance.database;
    final cleanQuery = _trim(search).toLowerCase();
    final whereClause = cleanQuery.isEmpty
        ? ''
        : '''
      WHERE LOWER(customers.name) LIKE ? OR customers.phone LIKE ?
    ''';
    final args = cleanQuery.isEmpty
        ? const <Object?>[]
        : ['%$cleanQuery%', '%${_trim(search)}%'];

    return db.rawQuery('''
      SELECT
        customers.id,
        customers.name,
        customers.phone,
        customers.last_purchase_date,
        COUNT(DISTINCT $_groupKeyExpr) AS orders_count,
        COALESCE(
          SUM(
            CASE
              WHEN sales.total > COALESCE(return_line_agg.returned_total, 0)
              THEN sales.total - COALESCE(return_line_agg.returned_total, 0)
              ELSE 0
            END
          ),
          0
        ) AS total_spent
      FROM customers
      LEFT JOIN sales
        ON sales.customer_id = customers.id
      LEFT JOIN (
        SELECT
          sale_id,
          SUM(refund_amount) AS returned_total
        FROM sale_returns
        GROUP BY sale_id
      ) return_line_agg
        ON return_line_agg.sale_id = sales.id
      $whereClause
      GROUP BY customers.id
      ORDER BY
        COALESCE(customers.last_purchase_date, customers.updated_at, customers.created_at) DESC,
        customers.name COLLATE NOCASE ASC
    ''', args);
  }

  Future<Map<String, dynamic>?> getCustomerById(int customerId) async {
    final db = await instance.database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<void> updateCustomer({
    required int customerId,
    required String name,
    required String phone,
  }) async {
    final db = await instance.database;
    final cleanName = _trim(name);
    final cleanPhone = _trim(phone);

    if (cleanName.isEmpty && cleanPhone.isEmpty) {
      throw Exception("Enter a customer name or phone number");
    }

    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'customers',
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      if (existingRows.isEmpty) {
        throw Exception("Customer not found");
      }

      if (cleanPhone.isNotEmpty) {
        final duplicatePhone = await txn.query(
          'customers',
          where: 'phone = ? AND id != ?',
          whereArgs: [cleanPhone, customerId],
          limit: 1,
        );
        if (duplicatePhone.isNotEmpty) {
          throw Exception("Another customer already uses this phone number");
        }
      }

      final existing = existingRows.first;
      final existingName = _trim(existing['name']?.toString());
      final updatedName = cleanName.isEmpty
          ? (existingName.isEmpty ? 'Customer' : existingName)
          : cleanName;
      final updatedPhone = cleanPhone.isEmpty ? null : cleanPhone;
      final updatedAt = _nowStamp();

      await txn.update(
        'customers',
        {'name': updatedName, 'phone': updatedPhone, 'updated_at': updatedAt},
        where: 'id = ?',
        whereArgs: [customerId],
      );

      await txn.update(
        'sales',
        {'customer_name': updatedName, 'customer_phone': updatedPhone},
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );

      await txn.update(
        'sale_returns',
        {'customer_name': updatedName, 'customer_phone': updatedPhone},
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getCustomerSaleOrders(
    int customerId,
  ) async {
    final db = await instance.database;
    return db.rawQuery(
      '''
      $_saleOrderSelect
      WHERE sales.customer_id = ?
      GROUP BY $_groupKeyExpr
      ORDER BY MAX(sales.date) DESC, MIN(sales.id) DESC
    ''',
      [customerId],
    );
  }

  Future<void> closeDatabase() async {
    if (_database == null) return;
    await _database!.close();
    _database = null;
  }

  Future<String> getRawDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _databaseName);
  }

  Future<String> getDatabasePath() async {
    final db = await instance.database;
    return db.path;
  }

  Future<File> createBackup(String targetPath) async {
    final dbPath = await getRawDatabasePath();
    final dbFile = File(dbPath);
    return dbFile.copy(targetPath);
  }

  Future<void> restoreDatabaseFromFile(String sourcePath) async {
    final destinationPath = await getRawDatabasePath();
    await closeDatabase();

    final sourceFile = File(sourcePath);
    final destinationFile = File(destinationPath);

    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }

    await sourceFile.copy(destinationPath);
  }
}
