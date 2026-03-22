import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const _databaseName = 'sales.db';
  static const _databaseVersion = 4;
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
        stock INTEGER NOT NULL
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
        bill_number TEXT
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
  }) async {
    final db = await instance.database;
    await db.update(
      'products',
      {
        'name': name,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'stock': stock,
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

  Future<String> createSaleOrder({
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
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
  }) async {
    final db = await instance.database;

    await db.transaction((txn) async {
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
        sales.discount,
        sales.total,
        sales.date,
        COALESCE(sales.cost_price, products.cost_price) AS cost_price,
        COALESCE(sales.selling_price, products.selling_price) AS selling_price,
        CASE
          WHEN COALESCE(sales.selling_price, products.selling_price) IS NOT NULL
          THEN COALESCE(sales.selling_price, products.selling_price) - sales.discount
          ELSE NULL
        END AS sold_price,
        CASE
          WHEN COALESCE(sales.cost_price, products.cost_price) IS NOT NULL
            AND COALESCE(sales.selling_price, products.selling_price) IS NOT NULL
          THEN (
            (COALESCE(sales.selling_price, products.selling_price) - sales.discount) -
            COALESCE(sales.cost_price, products.cost_price)
          ) * sales.units
          ELSE sales.profit
        END AS profit
      FROM sales
      LEFT JOIN products
        ON sales.product_id = products.id
      LEFT JOIN customers
        ON sales.customer_id = customers.id
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
        MAX(sales.date) AS date,
        COUNT(*) AS item_count,
        SUM(sales.units) AS total_units,
        SUM(sales.total) AS total,
        SUM(
          CASE
            WHEN COALESCE(sales.cost_price, products.cost_price) IS NOT NULL
              AND COALESCE(sales.selling_price, products.selling_price) IS NOT NULL
            THEN (
              (COALESCE(sales.selling_price, products.selling_price) - sales.discount) -
              COALESCE(sales.cost_price, products.cost_price)
            ) * sales.units
            ELSE sales.profit
          END
        ) AS profit,
        GROUP_CONCAT(
          COALESCE(NULLIF(TRIM(sales.product_name), ''), products.name, 'Deleted Product')
        ) AS product_names
      FROM sales
      LEFT JOIN products
        ON sales.product_id = products.id
      LEFT JOIN customers
        ON sales.customer_id = customers.id
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

  Future<Map<String, dynamic>> getTodaySummary() async {
    final db = await instance.database;
    final today = DateTime.now();
    final todayString =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final result = await db.rawQuery(
      '''
      SELECT
        COUNT(DISTINCT $_groupKeyExpr) AS total_sales,
        SUM(sales.total) AS total_revenue,
        SUM(
          CASE
            WHEN COALESCE(sales.cost_price, products.cost_price) IS NOT NULL
              AND COALESCE(sales.selling_price, products.selling_price) IS NOT NULL
            THEN (
              (COALESCE(sales.selling_price, products.selling_price) - sales.discount) -
              COALESCE(sales.cost_price, products.cost_price)
            ) * sales.units
            ELSE sales.profit
          END
        ) AS total_profit
      FROM sales
      LEFT JOIN products
        ON sales.product_id = products.id
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
        SUM(total) AS revenue
      FROM sales
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
        COALESCE(SUM(sales.total), 0) AS total_spent
      FROM customers
      LEFT JOIN sales
        ON sales.customer_id = customers.id
      $whereClause
      GROUP BY customers.id
      ORDER BY
        COALESCE(customers.last_purchase_date, customers.updated_at, customers.created_at) DESC,
        customers.name COLLATE NOCASE ASC
    ''', args);
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
