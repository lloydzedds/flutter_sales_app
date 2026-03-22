import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sales.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
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
        units INTEGER NOT NULL,
        discount REAL NOT NULL,
        total REAL NOT NULL,
        profit REAL NOT NULL,
        date TEXT NOT NULL,
        cost_price REAL,
        selling_price REAL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final columns = await db.rawQuery("PRAGMA table_info(sales)");
      final columnNames = columns
          .map((column) => column['name'] as String?)
          .whereType<String>()
          .toSet();

      if (!columnNames.contains('cost_price')) {
        await db.execute('ALTER TABLE sales ADD COLUMN cost_price REAL');
      }

      if (!columnNames.contains('selling_price')) {
        await db.execute('ALTER TABLE sales ADD COLUMN selling_price REAL');
      }
    }
  }

  Future<int> insertProduct(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('products', row);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await instance.database;
    return await db.query('products');
  }

  Future<int> insertSale(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('sales', row);
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
  Future<Map<String, dynamic>?> findProduct(
      String name, double price) async {
    final db = await instance.database;

    final result = await db.query(
      'products',
      where: 'name = ? AND selling_price = ?',
      whereArgs: [name, price],
    );

    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }
  Future<List<Map<String, dynamic>>> findByName(
      String name) async {
    final db = await instance.database;

    return await db.query(
      'products',
      where: 'name LIKE ?',
      whereArgs: ['$name%'],
    );
  }
  Future<void> deleteProduct(int id) async {
    final db = await instance.database;
    await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  Future<List<Map<String, dynamic>>> getSalesWithProduct() async {
    final db = await instance.database;

    return await db.rawQuery('''
      SELECT 
        sales.id,
        sales.product_id,
        sales.units,
        sales.discount,
        sales.total,
        sales.date,
        COALESCE(products.name, 'Deleted Product') AS name,
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
      ORDER BY sales.id DESC
    ''');
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
    final db = await instance.database;

    await db.transaction((txn) async {
      final existingSale = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
      );

      if (existingSale.isEmpty) {
        throw Exception('Sale not found');
      }

      final previousSale = existingSale.first;
      final oldProductId = previousSale['product_id'] as int;
      final oldUnits = previousSale['units'] as int;

      final oldProduct = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [oldProductId],
      );

      if (oldProduct.isNotEmpty) {
        final currentOldStock = oldProduct.first['stock'] as int;
        await txn.update(
          'products',
          {'stock': currentOldStock + oldUnits},
          where: 'id = ?',
          whereArgs: [oldProductId],
        );
      }

      final newProduct = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
      );

      if (newProduct.isEmpty) {
        throw Exception('Selected product not found');
      }

      final availableStock = newProduct.first['stock'] as int;
      if (units > availableStock) {
        throw Exception('Not enough stock');
      }

      await txn.update(
        'products',
        {'stock': availableStock - units},
        where: 'id = ?',
        whereArgs: [productId],
      );

      await txn.update(
        'sales',
        {
          'product_id': productId,
          'units': units,
          'discount': discount,
          'total': total,
          'profit': profit,
          'cost_price': costPrice,
          'selling_price': sellingPrice,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
  }

  Future<void> deleteSale(int saleId) async {
    final db = await instance.database;

    // Get sale details first
    final sale = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (sale.isNotEmpty) {
      final s = sale.first;

      int productId = s['product_id'] as int;
      int units = s['units'] as int;

      // Get current stock
      final product = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
      );

      if (product.isNotEmpty) {
        int currentStock = product.first['stock'] as int;

        await db.update(
          'products',
          {'stock': currentStock + units},
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
    }

    await db.delete(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }
  Future<Map<String, dynamic>> getTodaySummary() async {
    final db = await instance.database;

    final today = DateTime.now();
    final todayString =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_sales,
        SUM(total) as total_revenue,
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
        ) as total_profit
      FROM sales
      LEFT JOIN products
        ON sales.product_id = products.id
      WHERE sales.date LIKE ?
    ''', ['$todayString%']);

    return result.first;
  }
  Future<List<Map<String, dynamic>>> getSalesByDateRange(
      String startDate, String endDate) async {
    final db = await instance.database;

    return await db.rawQuery('''
      SELECT 
        sales.id,
        sales.product_id,
        sales.units,
        sales.discount,
        sales.total,
        sales.date,
        COALESCE(products.name, 'Deleted Product') AS name,
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
      WHERE sales.date BETWEEN ? AND ?
      ORDER BY sales.id DESC
    ''', [startDate, endDate]);
  }
  Future<List<Map<String, dynamic>>> getDailyRevenue() async {
    final db = await instance.database;

    return await db.rawQuery('''
      SELECT 
        SUBSTR(date,1,10) as day,
        SUM(total) as revenue
      FROM sales
      GROUP BY day
      ORDER BY day
    ''');
  }
  Future<String> getDatabasePath() async {
    final db = await instance.database;
    return db.path;
  }
}
