import 'dart:convert';

import 'package:http/http.dart' as http;

class ProductLookupResult {
  const ProductLookupResult({
    required this.barcode,
    required this.name,
    required this.source,
    this.brand,
    this.quantity,
  });

  final String barcode;
  final String name;
  final String source;
  final String? brand;
  final String? quantity;

  String get displayName {
    final cleanBrand = brand?.trim() ?? '';
    if (cleanBrand.isEmpty) return name;
    if (name.toLowerCase().contains(cleanBrand.toLowerCase())) return name;
    return "$cleanBrand $name";
  }
}

class ProductLookupService {
  ProductLookupService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const _fields = 'product_name,brands,generic_name,quantity';
  static const _sources = [
    _LookupSource(host: 'world.openfoodfacts.org', label: 'Open Food Facts'),
    _LookupSource(
      host: 'world.openproductsfacts.org',
      label: 'Open Products Facts',
    ),
  ];

  Future<ProductLookupResult?> findByBarcode(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;

    if (!_looksLikeProductBarcode(cleanBarcode)) {
      throw const ProductLookupException(
        "This looks like a QR or serial code, not a UPC/EAN product barcode. Save the product manually once and future scans will match it locally.",
      );
    }

    final requestClient = _client ?? http.Client();
    try {
      ProductLookupException? lastError;

      for (final source in _sources) {
        try {
          final result = await _lookupSource(
            requestClient,
            source,
            cleanBarcode,
          );
          if (result != null) return result;
        } on ProductLookupException catch (error) {
          lastError = error;
        }
      }

      if (lastError != null) throw lastError;
      return null;
    } on ProductLookupException {
      rethrow;
    } catch (_) {
      throw const ProductLookupException("Could not look up this barcode");
    } finally {
      if (_client == null) {
        requestClient.close();
      }
    }
  }

  Future<ProductLookupResult?> _lookupSource(
    http.Client requestClient,
    _LookupSource source,
    String barcode,
  ) async {
    final uri = Uri.https(source.host, '', {
      'fields': _fields,
    }).replace(pathSegments: ['api', 'v2', 'product', '$barcode.json']);

    final response = await requestClient
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'SaleBuddy/1.0 (Flutter inventory app)',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProductLookupException(
        "${source.label} lookup failed with status ${response.statusCode}",
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['status'] != 1) return null;

    final product = decoded['product'];
    if (product is! Map<String, dynamic>) return null;

    final productName = _cleanText(product['product_name']);
    final genericName = _cleanText(product['generic_name']);
    final brands = _cleanText(product['brands']);
    final quantity = _cleanText(product['quantity']);
    final name = productName.isNotEmpty ? productName : genericName;

    if (name.isEmpty && brands.isEmpty) return null;

    return ProductLookupResult(
      barcode: barcode,
      name: name.isNotEmpty ? name : brands,
      source: source.label,
      brand: brands.isEmpty ? null : brands,
      quantity: quantity.isEmpty ? null : quantity,
    );
  }

  static bool _looksLikeProductBarcode(String value) {
    return RegExp(r'^\d{8,14}$').hasMatch(value);
  }

  static String _cleanText(dynamic value) {
    return value?.toString().trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
  }
}

class _LookupSource {
  const _LookupSource({required this.host, required this.label});

  final String host;
  final String label;
}

class ProductLookupException implements Exception {
  const ProductLookupException(this.message);

  final String message;

  @override
  String toString() => message;
}
