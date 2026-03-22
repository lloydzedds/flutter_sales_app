import 'dart:typed_data';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import 'add_product_screen.dart';
import 'add_sale_screen.dart';
import 'customers_screen.dart';
import 'settings_screen.dart';
import 'sales_history_screen.dart';
import 'stock_adjust_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _background = Color(0xFF16131D);
  static const _surface = Color(0xFF211D27);
  static const _surfaceSoft = Color(0xFF2A2432);
  static const _accent = Color(0xFF8B5FE8);
  static const _border = Color(0xFF312A3A);
  static const double _headerReservedSpace = 108;

  int _selectedTab = 0;
  bool _isLoading = true;
  bool _isHeaderScrolled = false;
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );

  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> recentSales = [];
  List<Map<String, dynamic>> rangedSales = [];
  List<Map<String, dynamic>> topProducts = [];
  List<Map<String, dynamic>> revenueSeries = [];

  double totalRevenue = 0;
  double totalProfit = 0;
  int totalSales = 0;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    final start = DateFormat('yyyy-MM-dd').format(_selectedRange.start);
    final end = DateFormat('yyyy-MM-dd').format(_selectedRange.end);

    final productsFuture = DatabaseHelper.instance.getProducts();
    final allSalesFuture = DatabaseHelper.instance.getSalesWithProduct();
    final filteredSalesFuture = DatabaseHelper.instance.getSalesByDateRange(
      "$start 00:00",
      "$end 23:59",
    );
    final revenueDataFuture = DatabaseHelper.instance.getDailyRevenue();

    final fetchedProducts = await productsFuture;
    final allSales = await allSalesFuture;
    final filteredSales = await filteredSalesFuture;
    final revenueData = await revenueDataFuture;

    if (!mounted) return;

    setState(() {
      products = fetchedProducts;
      recentSales = allSales.take(5).toList();
      rangedSales = filteredSales;
      topProducts = _buildTopProducts(allSales);
      revenueSeries = _buildRevenueSeries(revenueData);
      totalRevenue = _sumByKey(filteredSales, 'total');
      totalProfit = _sumByKey(filteredSales, 'profit');
      totalSales = filteredSales.length;
      _isLoading = false;
    });
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _sumByKey(List<Map<String, dynamic>> rows, String key) {
    double total = 0;
    for (final row in rows) {
      total += _asDouble(row[key]);
    }
    return total;
  }

  String _formatMoney(dynamic value) {
    final amount = _asDouble(value);
    if (amount == amount.roundToDouble()) {
      return "Rs ${amount.toStringAsFixed(0)}";
    }
    return "Rs ${amount.toStringAsFixed(2)}";
  }

  Uint8List? _productPhotoBytes(Map<String, dynamic> product) {
    final value = product['photo_bytes'];
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    return null;
  }

  Widget _buildProductAvatar(Map<String, dynamic> product) {
    final bytes = _productPhotoBytes(product);

    return Container(
      height: 54,
      width: 54,
      decoration: BoxDecoration(
        color: _accent.withAlpha(28),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? const Icon(Icons.inventory_2_outlined, color: Colors.white)
          : Image.memory(bytes, fit: BoxFit.cover),
    );
  }

  int get _productCount => products.length;

  int get _lowStockCount => products
      .where(
        (product) =>
            _asInt(product['stock']) > 0 && _asInt(product['stock']) <= 5,
      )
      .length;

  int get _outOfStockCount =>
      products.where((product) => _asInt(product['stock']) == 0).length;

  List<Map<String, dynamic>> get _lowStockProducts =>
      products.where((product) => _asInt(product['stock']) <= 5).toList();

  List<Map<String, dynamic>> _buildTopProducts(
    List<Map<String, dynamic>> sales,
  ) {
    final totals = <String, Map<String, dynamic>>{};

    for (final sale in sales) {
      final name = sale['name']?.toString() ?? 'Unknown Product';
      final entry = totals.putIfAbsent(name, () {
        return {'name': name, 'units': 0, 'revenue': 0.0};
      });
      entry['units'] = _asInt(entry['units']) + _asInt(sale['units']);
      entry['revenue'] = _asDouble(entry['revenue']) + _asDouble(sale['total']);
    }

    final sorted = totals.values.toList()
      ..sort((a, b) => _asInt(b['units']).compareTo(_asInt(a['units'])));
    return sorted.take(5).toList();
  }

  List<Map<String, dynamic>> _buildRevenueSeries(
    List<Map<String, dynamic>> allRevenue,
  ) {
    final revenueByDay = <String, double>{};
    for (final row in allRevenue) {
      final day = row['day']?.toString();
      if (day == null) continue;
      revenueByDay[day] = _asDouble(row['revenue']);
    }

    final days = <Map<String, dynamic>>[];
    var cursor = DateTime(
      _selectedRange.start.year,
      _selectedRange.start.month,
      _selectedRange.start.day,
    );
    final end = DateTime(
      _selectedRange.end.year,
      _selectedRange.end.month,
      _selectedRange.end.day,
    );

    while (!cursor.isAfter(end)) {
      final dayKey = DateFormat('yyyy-MM-dd').format(cursor);
      days.add({
        'label': DateFormat('M/d').format(cursor),
        'revenue': revenueByDay[dayKey] ?? 0.0,
      });
      cursor = cursor.add(const Duration(days: 1));
    }

    return days;
  }

  String _rangeTitle() {
    final days = _selectedRange.end.difference(_selectedRange.start).inDays + 1;
    return days == 7 ? "Last 7 Days" : "Selected Range";
  }

  String _rangeSubtitle() {
    final formatter = DateFormat('M/d/yyyy');
    return "${formatter.format(_selectedRange.start)} - ${formatter.format(_selectedRange.end)}";
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedRange,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: _accent, surface: _surface),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _selectedRange = DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
      _isLoading = true;
    });

    await loadDashboard();
  }

  Future<void> _pushAndRefresh(Widget screen) async {
    final navigator = Navigator.of(context);
    await navigator.push(MaterialPageRoute(builder: (_) => screen));

    if (!mounted) return;
    await loadDashboard();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openStockAdjustment({
    Map<String, dynamic>? product,
    StockAdjustMode mode = StockAdjustMode.add,
  }) async {
    await _pushAndRefresh(
      StockAdjustScreen(
        initialProductId: product?['id'] as int?,
        initialMode: mode,
      ),
    );
  }

  Future<void> _openProductEditor(Map<String, dynamic> product) async {
    await _pushAndRefresh(AddProductScreen(initialProduct: product));
  }

  Future<void> _handleProductLongPress(Map<String, dynamic> product) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text("Edit Product"),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text("Add Stock"),
                onTap: () => Navigator.of(sheetContext).pop('add'),
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text("Remove Stock"),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("Set Exact Stock"),
                onTap: () => Navigator.of(sheetContext).pop('set'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'edit':
        await _openProductEditor(product);
        return;
      case 'add':
        await _openStockAdjustment(product: product, mode: StockAdjustMode.add);
        return;
      case 'remove':
        await _openStockAdjustment(
          product: product,
          mode: StockAdjustMode.remove,
        );
        return;
      case 'set':
        await _openStockAdjustment(product: product, mode: StockAdjustMode.set);
        return;
    }
  }

  String _currentTabTitle() {
    switch (_selectedTab) {
      case 0:
        return "Dashboard";
      case 1:
        return "Sales";
      case 2:
        return "Inventory";
      case 3:
        return "Stock Control";
      case 4:
        return "Reports";
      default:
        return "Dashboard";
    }
  }

  String _currentTabSubtitle() {
    switch (_selectedTab) {
      case 0:
        return "A dark sales cockpit for your daily business";
      case 1:
        return "Create orders and review recent transactions";
      case 2:
        return "Manage products and quick stock edits";
      case 3:
        return "Keep inventory healthy and react fast";
      case 4:
        return "Range based performance for sales and revenue";
      default:
        return "A dark sales cockpit for your daily business";
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final isScrolled = notification.metrics.pixels > 10;
    if (isScrolled == _isHeaderScrolled) {
      return false;
    }

    setState(() {
      _isHeaderScrolled = isScrolled;
    });
    return false;
  }

  Widget _buildPinnedHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _isHeaderScrolled ? 18 : 0,
            sigmaY: _isHeaderScrolled ? 18 : 0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: _isHeaderScrolled
                  ? _background.withAlpha(212)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: _isHeaderScrolled
                    ? Colors.white.withAlpha(18)
                    : Colors.transparent,
              ),
              boxShadow: _isHeaderScrolled
                  ? [
                      const BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentTabTitle(),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentTabSubtitle(),
                        style: TextStyle(
                          color: Colors.white.withAlpha(166),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0E6BBE), Color(0xFF0B4D86)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: IconButton(
                    onPressed: () => _pushAndRefresh(const SettingsScreen()),
                    icon: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: _surface,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    onPressed: () => _showMessage("No notifications yet"),
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableTab(List<Widget> children) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, _headerReservedSpace, 16, 32),
        children: children,
      ),
    );
  }

  Widget _buildPromoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF9B6DFF), Color(0xFF7E59D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33261A46),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(41),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.auto_graph_rounded, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Sales Manager Dashboard",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  "Track revenue, products, stock and recent sales from one place.",
                  style: TextStyle(fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        ],
      ),
    );
  }

  Widget _buildDateRangeCard() {
    return InkWell(
      onTap: _pickDateRange,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.calendar_month_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _rangeTitle(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _rangeSubtitle(),
                    style: TextStyle(color: Colors.white.withAlpha(158)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
    String? caption,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withAlpha(230),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(36),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption,
              style: TextStyle(
                color: Colors.white.withAlpha(140),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricPill({
    required String label,
    required Color color,
    Color? backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withAlpha(32),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }

  Widget _buildProfitMetricCard() {
    final isLoss = totalProfit < 0;
    final isNeutral = totalProfit == 0;
    final accentColor = isLoss
        ? const Color(0xFFFF7D7D)
        : isNeutral
        ? Colors.white.withAlpha(204)
        : const Color(0xFFB785FF);
    final resultLabel = isLoss
        ? "Loss"
        : isNeutral
        ? "Break-even"
        : "Profit";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Profit",
                  style: TextStyle(
                    color: Colors.white.withAlpha(230),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(36),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isLoss
                      ? Icons.trending_down_rounded
                      : Icons.account_balance_wallet_outlined,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            _formatMoney(isLoss ? totalProfit.abs() : totalProfit),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _buildMetricPill(label: resultLabel, color: accentColor),
          const SizedBox(height: 10),
          Text(
            "Based on the selected date range",
            style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsMetricCard() {
    final healthyCount = products.where((product) {
      final stock = _asInt(product['stock']);
      return stock > 5;
    }).length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Products",
                  style: TextStyle(
                    color: Colors.white.withAlpha(230),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB43A).withAlpha(36),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.inventory_2_rounded,
                  color: Color(0xFFFFB43A),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            "$_productCount",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            "$healthyCount healthy in inventory",
            style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetricPill(
                label: "Low $_lowStockCount",
                color: const Color(0xFFFFB43A),
              ),
              _buildMetricPill(
                label: "Out $_outOfStockCount",
                color: const Color(0xFFFF7D7D),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withAlpha(153),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildPrimaryActionButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _pushAndRefresh(const AddSaleScreen()),
        icon: const Icon(Icons.shopping_cart_checkout_rounded),
        label: const Text("New Order"),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildRecentSalesList(List<Map<String, dynamic>> sales) {
    if (sales.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.show_chart_rounded,
                size: 32,
                color: Colors.white.withAlpha(179),
              ),
              const SizedBox(height: 12),
              Text(
                "No data available",
                style: TextStyle(
                  color: Colors.white.withAlpha(191),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: sales.map((sale) {
        final profit = _asDouble(sale['profit']);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surfaceSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF18293F),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: Color(0xFF61A8FF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale['name']?.toString() ?? 'Sale',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Units ${sale['units']} - ${sale['date']}",
                      style: TextStyle(
                        color: Colors.white.withAlpha(158),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatMoney(sale['total']),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profit < 0
                        ? "Loss ${_formatMoney(profit.abs())}"
                        : "Profit ${_formatMoney(profit)}",
                    style: TextStyle(
                      color: profit < 0
                          ? Colors.redAccent
                          : const Color(0xFF56D47A),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTopProductsList() {
    if (topProducts.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            "No product sales yet",
            style: TextStyle(color: Colors.white.withAlpha(184)),
          ),
        ),
      );
    }

    return Column(
      children: topProducts.asMap().entries.map((entry) {
        final index = entry.key;
        final product = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surfaceSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A2A14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  "${index + 1}",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  product['name'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${product['units']} sold"),
                  Text(
                    _formatMoney(product['revenue']),
                    style: TextStyle(color: Colors.white.withAlpha(166)),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildProductItem(Map<String, dynamic> product) {
    final stock = _asInt(product['stock']);
    final isOut = stock == 0;
    final isLow = stock > 0 && stock <= 5;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        onLongPress: () => _handleProductLongPress(product),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildProductAvatar(product),
        title: Text(
          product['name'].toString(),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isOut
                ? Colors.redAccent
                : isLow
                ? Colors.orangeAccent
                : Colors.white,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            "Stock: $stock - ${_formatMoney(product['selling_price'])}",
            style: TextStyle(color: Colors.white.withAlpha(173)),
          ),
        ),
        trailing: isOut
            ? const _StatusChip(label: "OUT", color: Colors.red)
            : isLow
            ? const _StatusChip(label: "LOW", color: Colors.orange)
            : const Icon(Icons.more_horiz_rounded),
      ),
    );
  }

  Widget _buildStockActionList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Text(
        "Everything looks healthy right now.",
        style: TextStyle(color: Colors.white.withAlpha(166)),
      );
    }

    return Column(
      children: items.map((product) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surfaceSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Current stock: ${product['stock']}",
                      style: TextStyle(color: Colors.white.withAlpha(168)),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => _handleProductLongPress(product),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent.withAlpha(46),
                  foregroundColor: Colors.white,
                ),
                child: const Text("Adjust"),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildReportsChart() {
    if (revenueSeries.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            "No revenue data for this range",
            style: TextStyle(color: Colors.white.withAlpha(179)),
          ),
        ),
      );
    }

    final maxY = revenueSeries
        .map((point) => _asDouble(point['revenue']))
        .fold<double>(
          0,
          (previous, element) => element > previous ? element : previous,
        );
    final effectiveMax = maxY <= 0 ? 10.0 : maxY * 1.2;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: effectiveMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: effectiveMax / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white.withAlpha(20), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: effectiveMax / 4,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value == value.roundToDouble()
                        ? value.toStringAsFixed(0)
                        : value.toStringAsFixed(1),
                    style: TextStyle(
                      color: Colors.white.withAlpha(128),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= revenueSeries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      revenueSeries[index]['label'].toString(),
                      style: TextStyle(
                        color: Colors.white.withAlpha(140),
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: revenueSeries.asMap().entries.map((entry) {
                return FlSpot(
                  entry.key.toDouble(),
                  _asDouble(entry.value['revenue']),
                );
              }).toList(),
              isCurved: true,
              barWidth: 4,
              color: _accent,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_accent.withAlpha(89), _accent.withAlpha(0)],
                ),
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: _accent,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceSoft,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(36),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withAlpha(158),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMetric({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(158))),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withAlpha(173)),
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildTabContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_selectedTab) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildSalesTab();
      case 2:
        return _buildInventoryTab();
      case 3:
        return _buildStockTab();
      case 4:
        return _buildReportsTab();
      default:
        return _buildDashboardTab();
    }
  }

  Widget _buildDashboardTab() {
    return _buildScrollableTab([
      _buildPromoCard(),
      const SizedBox(height: 16),
      _buildDateRangeCard(),
      const SizedBox(height: 16),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 204,
        ),
        children: [
          _buildMetricCard(
            label: "Revenue",
            value: _formatMoney(totalRevenue),
            icon: Icons.trending_up_rounded,
            accentColor: const Color(0xFF57D77F),
          ),
          _buildMetricCard(
            label: "Sales",
            value: "$totalSales",
            icon: Icons.receipt_long_rounded,
            accentColor: const Color(0xFF5F95FF),
          ),
          _buildProfitMetricCard(),
          _buildProductsMetricCard(),
        ],
      ),
      const SizedBox(height: 16),
      _buildPrimaryActionButton(),
      const SizedBox(height: 16),
      _buildPanel(
        title: "Recent Sales",
        subtitle: "Latest activity in the business",
        trailing: TextButton(
          onPressed: () => _pushAndRefresh(const SalesHistoryScreen()),
          child: const Text("View all"),
        ),
        child: _buildRecentSalesList(recentSales),
      ),
      const SizedBox(height: 16),
      _buildPanel(
        title: "Top Selling Products",
        subtitle: "Best movers by units sold",
        child: _buildTopProductsList(),
      ),
    ]);
  }

  Widget _buildSalesTab() {
    return _buildScrollableTab([
      _buildPanel(
        title: "Quick Actions",
        child: Column(
          children: [
            _buildWideActionTile(
              title: "Record Sale",
              subtitle: "Create a new multi-product order",
              icon: Icons.shopping_cart_checkout_rounded,
              color: _accent,
              onTap: () => _pushAndRefresh(const AddSaleScreen()),
            ),
            const SizedBox(height: 12),
            _buildWideActionTile(
              title: "Sales History",
              subtitle: "Review orders, export records, and share bills",
              icon: Icons.history_rounded,
              color: const Color(0xFF4B8CFF),
              onTap: () => _pushAndRefresh(const SalesHistoryScreen()),
            ),
            const SizedBox(height: 12),
            _buildWideActionTile(
              title: "Customers",
              subtitle: "Search customers and open their purchase history",
              icon: Icons.people_alt_outlined,
              color: const Color(0xFF57D77F),
              onTap: () => _pushAndRefresh(const CustomersScreen()),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _buildPanel(
        title: "Recent Sales",
        subtitle: "Long press in history for more actions",
        child: _buildRecentSalesList(recentSales),
      ),
    ]);
  }

  Widget _buildInventoryTab() {
    return _buildScrollableTab([
      _buildPanel(
        title: "Inventory Snapshot",
        child: Row(
          children: [
            Expanded(
              child: _buildMiniMetric(
                label: "Products",
                value: "$_productCount",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMiniMetric(
                label: "Low Stock",
                value: "$_lowStockCount",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMiniMetric(label: "Out", value: "$_outOfStockCount"),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _buildPanel(
        title: "Quick Actions",
        child: Column(
          children: [
            _buildWideActionTile(
              title: "Add Product",
              subtitle: "Create a new product in inventory",
              icon: Icons.add_box_outlined,
              color: const Color(0xFFFFB43A),
              onTap: () => _pushAndRefresh(const AddProductScreen()),
            ),
            const SizedBox(height: 12),
            _buildWideActionTile(
              title: "Stock Adjustment",
              subtitle: "Add, remove or set exact stock values",
              icon: Icons.tune_rounded,
              color: const Color(0xFF57D77F),
              onTap: () => _openStockAdjustment(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _buildPanel(
        title: "Products",
        subtitle: "Long press any product to edit details or adjust stock",
        child: products.isEmpty
            ? Text(
                "No products added yet",
                style: TextStyle(color: Colors.white.withAlpha(179)),
              )
            : Column(children: products.map(_buildProductItem).toList()),
      ),
    ]);
  }

  Widget _buildStockTab() {
    return _buildScrollableTab([
      _buildPanel(
        title: "Adjust Stock",
        subtitle: "Open the stock editor for manual updates",
        child: _buildWideActionTile(
          title: "Open Stock Adjustment",
          subtitle: "Add, remove or set exact stock",
          icon: Icons.inventory_2_outlined,
          color: _accent,
          onTap: () => _openStockAdjustment(),
        ),
      ),
      const SizedBox(height: 16),
      _buildPanel(
        title: "Products Needing Attention",
        subtitle: "Tap adjust to change stock quickly",
        child: _buildStockActionList(_lowStockProducts),
      ),
    ]);
  }

  Widget _buildReportsTab() {
    return _buildScrollableTab([
      _buildDateRangeCard(),
      const SizedBox(height: 16),
      _buildPanel(
        title: "Revenue Trend",
        subtitle: "Selected range",
        child: _buildReportsChart(),
      ),
      const SizedBox(height: 16),
      _buildPanel(
        title: "Range Summary",
        child: Column(
          children: [
            _buildSummaryRow("Revenue", _formatMoney(totalRevenue)),
            const SizedBox(height: 10),
            _buildSummaryRow("Profit", _formatMoney(totalProfit)),
            const SizedBox(height: 10),
            _buildSummaryRow("Sales Count", "$totalSales"),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _pushAndRefresh(const SalesHistoryScreen()),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text("Open Sales History"),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: KeyedSubtree(
                  key: ValueKey(_selectedTab),
                  child: _buildTabContent(),
                ),
              ),
            ),
            Positioned(left: 0, right: 0, top: 0, child: _buildPinnedHeader()),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 78,
        backgroundColor: const Color(0xFF1B1721),
        indicatorColor: _accent,
        selectedIndex: _selectedTab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
            _isHeaderScrolled = false;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: "Dashboard",
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart_rounded),
            label: "Sales",
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: "Inventory",
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: "Stock",
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: "Reports",
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(46),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
