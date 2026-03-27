import 'dart:typed_data';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import 'add_product_screen.dart';
import 'add_sale_screen.dart';
import 'customers_screen.dart';
import 'how_to_use_screen.dart';
import 'settings_screen.dart';
import 'sales_history_screen.dart';
import 'stock_adjust_screen.dart';

enum _DashboardRangePreset {
  today,
  yesterday,
  last7Days,
  last30Days,
  previousMonth,
  custom,
}

enum _InventorySortOption {
  nameAsc,
  nameDesc,
  priceAsc,
  priceDesc,
  stockAsc,
  stockDesc,
}

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
  final TextEditingController _inventorySearchController =
      TextEditingController();
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );
  _DashboardRangePreset _selectedRangePreset = _DashboardRangePreset.last7Days;
  String _inventorySearchQuery = '';
  _InventorySortOption _inventorySortOption = _InventorySortOption.nameAsc;

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

  @override
  void dispose() {
    _inventorySearchController.dispose();
    super.dispose();
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

  List<Map<String, dynamic>> get _visibleProducts {
    final query = _inventorySearchQuery.trim().toLowerCase();
    final filtered = products.where((product) {
      if (query.isEmpty) {
        return true;
      }

      final name = product['name']?.toString().toLowerCase() ?? '';
      return name.contains(query);
    }).toList();

    filtered.sort((a, b) {
      switch (_inventorySortOption) {
        case _InventorySortOption.nameAsc:
          return _compareProductNames(a, b);
        case _InventorySortOption.nameDesc:
          return _compareProductNames(b, a);
        case _InventorySortOption.priceAsc:
          final priceComparison = _asDouble(
            a['selling_price'],
          ).compareTo(_asDouble(b['selling_price']));
          return priceComparison != 0
              ? priceComparison
              : _compareProductNames(a, b);
        case _InventorySortOption.priceDesc:
          final priceComparison = _asDouble(
            b['selling_price'],
          ).compareTo(_asDouble(a['selling_price']));
          return priceComparison != 0
              ? priceComparison
              : _compareProductNames(a, b);
        case _InventorySortOption.stockAsc:
          final stockComparison = _asInt(
            a['stock'],
          ).compareTo(_asInt(b['stock']));
          return stockComparison != 0
              ? stockComparison
              : _compareProductNames(a, b);
        case _InventorySortOption.stockDesc:
          final stockComparison = _asInt(
            b['stock'],
          ).compareTo(_asInt(a['stock']));
          return stockComparison != 0
              ? stockComparison
              : _compareProductNames(a, b);
      }
    });

    return filtered;
  }

  int _compareProductNames(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftName = left['name']?.toString().toLowerCase() ?? '';
    final rightName = right['name']?.toString().toLowerCase() ?? '';
    return leftName.compareTo(rightName);
  }

  List<Map<String, dynamic>> _buildTopProducts(
    List<Map<String, dynamic>> sales,
  ) {
    final totals = <String, Map<String, dynamic>>{};

    for (final sale in sales) {
      final name = sale['name']?.toString() ?? 'Unknown Product';
      final entry = totals.putIfAbsent(name, () {
        return {'name': name, 'units': 0, 'revenue': 0.0};
      });
      entry['units'] =
          _asInt(entry['units']) + _asInt(sale['net_units'] ?? sale['units']);
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

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _rangePresetLabel(_DashboardRangePreset preset) {
    switch (preset) {
      case _DashboardRangePreset.today:
        return "Today";
      case _DashboardRangePreset.yesterday:
        return "Yesterday";
      case _DashboardRangePreset.last7Days:
        return "Last 7 Days";
      case _DashboardRangePreset.last30Days:
        return "Last 30 Days";
      case _DashboardRangePreset.previousMonth:
        return "Previous Month";
      case _DashboardRangePreset.custom:
        return "Custom Range";
    }
  }

  String _rangeTitle() {
    return _rangePresetLabel(_selectedRangePreset);
  }

  String _rangeSubtitle() {
    final formatter = DateFormat('M/d/yyyy');
    return "${formatter.format(_selectedRange.start)} - ${formatter.format(_selectedRange.end)}";
  }

  String _inventorySortLabel(_InventorySortOption option) {
    switch (option) {
      case _InventorySortOption.nameAsc:
        return "Name (A to Z)";
      case _InventorySortOption.nameDesc:
        return "Name (Z to A)";
      case _InventorySortOption.priceAsc:
        return "Price (Low to High)";
      case _InventorySortOption.priceDesc:
        return "Price (High to Low)";
      case _InventorySortOption.stockAsc:
        return "Stock (Low to High)";
      case _InventorySortOption.stockDesc:
        return "Stock (High to Low)";
    }
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTab = index;
      _isHeaderScrolled = false;
    });
  }

  Future<void> _applyDateRange(
    DateTimeRange range, {
    required _DashboardRangePreset preset,
  }) async {
    setState(() {
      _selectedRange = DateTimeRange(
        start: _dateOnly(range.start),
        end: _dateOnly(range.end),
      );
      _selectedRangePreset = preset;
      _isLoading = true;
    });

    await loadDashboard();
  }

  Future<DateTimeRange?> _pickCustomDateRange() async {
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

    if (picked == null) return null;
    return DateTimeRange(
      start: _dateOnly(picked.start),
      end: _dateOnly(picked.end),
    );
  }

  Future<void> _pickDateRange() async {
    final now = _dateOnly(DateTime.now());
    final previousMonthStart = DateTime(now.year, now.month - 1, 1);
    final previousMonthEnd = DateTime(now.year, now.month, 0);

    final selection = await showModalBottomSheet<_DashboardRangePreset>(
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
                leading: const Icon(Icons.today_outlined),
                title: const Text("Today"),
                subtitle: const Text("Show only today's sales"),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_DashboardRangePreset.today),
              ),
              ListTile(
                leading: const Icon(Icons.history_toggle_off_rounded),
                title: const Text("Yesterday"),
                subtitle: const Text("Show the previous day's sales"),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_DashboardRangePreset.yesterday),
              ),
              ListTile(
                leading: const Icon(Icons.date_range_outlined),
                title: const Text("Last 7 Days"),
                subtitle: const Text("Include today and the past 6 days"),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_DashboardRangePreset.last7Days),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_view_month_outlined),
                title: const Text("Last 30 Days"),
                subtitle: const Text("Include today and the past 29 days"),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_DashboardRangePreset.last30Days),
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: const Text("Previous Month"),
                subtitle: Text(
                  DateFormat('MMMM yyyy').format(previousMonthStart),
                ),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_DashboardRangePreset.previousMonth),
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text("Custom Range"),
                subtitle: const Text("Choose any start and end dates"),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_DashboardRangePreset.custom),
              ),
            ],
          ),
        );
      },
    );

    if (selection == null) return;

    switch (selection) {
      case _DashboardRangePreset.today:
        await _applyDateRange(
          DateTimeRange(start: now, end: now),
          preset: selection,
        );
        return;
      case _DashboardRangePreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        await _applyDateRange(
          DateTimeRange(start: yesterday, end: yesterday),
          preset: selection,
        );
        return;
      case _DashboardRangePreset.last7Days:
        await _applyDateRange(
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
          preset: selection,
        );
        return;
      case _DashboardRangePreset.last30Days:
        await _applyDateRange(
          DateTimeRange(
            start: now.subtract(const Duration(days: 29)),
            end: now,
          ),
          preset: selection,
        );
        return;
      case _DashboardRangePreset.previousMonth:
        await _applyDateRange(
          DateTimeRange(start: previousMonthStart, end: previousMonthEnd),
          preset: selection,
        );
        return;
      case _DashboardRangePreset.custom:
        final picked = await _pickCustomDateRange();
        if (picked == null) return;
        await _applyDateRange(picked, preset: selection);
        return;
    }
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
    return InkWell(
      onTap: () => _pushAndRefresh(const HowToUseScreen()),
      borderRadius: BorderRadius.circular(24),
      child: Container(
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
                    "Sale Buddy / My Accounts",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Track revenue, products, stock and recent sales from one place.",
                    style: TextStyle(fontSize: 12.5, height: 1.35),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "Tap to open the quick guide",
                    style: TextStyle(fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ],
        ),
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
    String? actionLabel,
    VoidCallback? onTap,
  }) {
    final card = Container(
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
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  actionLabel,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: accentColor),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: card,
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

  Widget _buildProductsMetricCard({String? actionLabel, VoidCallback? onTap}) {
    final healthyCount = products.where((product) {
      final stock = _asInt(product['stock']);
      return stock > 5;
    }).length;

    final card = Container(
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
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  actionLabel,
                  style: const TextStyle(
                    color: Color(0xFFFFB43A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFFFFB43A),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: card,
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
                      "Units ${sale['net_units'] ?? sale['units']} - ${sale['date']}",
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

  Widget _buildInventoryControls(int visibleCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _inventorySearchController,
          onChanged: (value) {
            setState(() {
              _inventorySearchQuery = value;
            });
          },
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Search products by name",
            hintStyle: TextStyle(color: Colors.white.withAlpha(132)),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: Colors.white.withAlpha(168),
            ),
            suffixIcon: _inventorySearchQuery.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _inventorySearchController.clear();
                      setState(() {
                        _inventorySearchQuery = '';
                      });
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withAlpha(168),
                    ),
                  ),
            filled: true,
            fillColor: _surfaceSoft,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _accent, width: 1.2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Showing $visibleCount of $_productCount products",
          style: TextStyle(
            color: Colors.white.withAlpha(150),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<_InventorySortOption>(
          initialValue: _inventorySortOption,
          dropdownColor: _surface,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: "Sort products",
            labelStyle: TextStyle(color: Colors.white.withAlpha(150)),
            filled: true,
            fillColor: _surfaceSoft,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _accent, width: 1.2),
            ),
          ),
          iconEnabledColor: Colors.white,
          items: _InventorySortOption.values.map((option) {
            return DropdownMenuItem<_InventorySortOption>(
              value: option,
              child: Text(
                _inventorySortLabel(option),
                style: const TextStyle(color: Colors.white),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _inventorySortOption = value;
            });
          },
        ),
      ],
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
            actionLabel: "Open reports",
            onTap: () => _selectTab(4),
          ),
          _buildProfitMetricCard(),
          _buildProductsMetricCard(
            actionLabel: "Open inventory",
            onTap: () => _selectTab(2),
          ),
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
    final visibleProducts = _visibleProducts;

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
        subtitle:
            "Search, sort, and long press any product to edit or adjust stock",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInventoryControls(visibleProducts.length),
            const SizedBox(height: 16),
            if (products.isEmpty)
              Text(
                "No products added yet",
                style: TextStyle(color: Colors.white.withAlpha(179)),
              )
            else if (visibleProducts.isEmpty)
              Text(
                "No products match your search",
                style: TextStyle(color: Colors.white.withAlpha(179)),
              )
            else
              Column(children: visibleProducts.map(_buildProductItem).toList()),
          ],
        ),
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
        onDestinationSelected: _selectTab,
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
