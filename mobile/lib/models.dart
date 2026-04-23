int _toInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim()) ?? fallback;
}

int? _toNullableInt(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(text);
}

List<int> _toIntList(dynamic value) {
  if (value is List) {
    final out = <int>[];
    for (final item in value) {
      final id = _toNullableInt(item);
      if (id != null && !out.contains(id)) {
        out.add(id);
      }
    }
    return out;
  }
  final single = _toNullableInt(value);
  return single == null ? const [] : [single];
}

double _toDouble(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim()) ?? fallback;
}

double? _toNullableDouble(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(text);
}

String? _toNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

class Tenant {
  final int id;
  final String name;
  final String? logoPath;

  Tenant({required this.id, required this.name, this.logoPath});

  factory Tenant.fromJson(Map<String, dynamic> j) => Tenant(
        id: _toInt(j['id']),
        name: (j['name'] ?? '').toString(),
        logoPath: _toNullableString(j['logo_path']),
      );
}

class Location {
  final int id;
  final String name;
  final String type; // SHOP/WAREHOUSE

  Location({required this.id, required this.name, required this.type});

  factory Location.fromJson(Map<String, dynamic> j) => Location(
        id: _toInt(j['id']),
        name: (j['name'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
      );
}

class UserProfile {
  final int id;
  final String name;
  final String email;
  final String role;
  final String? displayRole;
  final int tenantId;
  final int? locationId;
  final List<int> locationIds;
  final List<String> permissions;
  final List<String> rights;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.displayRole,
    required this.tenantId,
    required this.locationId,
    this.locationIds = const [],
    this.permissions = const [],
    this.rights = const [],
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    final locationId = _toNullableInt(j['location_id']);
    final locationIds = _toIntList(j['location_ids']);
    final permissions = ((j['permissions'] as List?) ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final rights = ((j['rights'] as List?) ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return UserProfile(
      id: _toInt(j['id']),
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      role: (j['role'] ?? '').toString(),
      displayRole: _toNullableString(j['display_role']),
      tenantId: _toInt(j['tenant_id']),
      locationId: locationId,
      locationIds: locationIds.isNotEmpty
          ? locationIds
          : (locationId == null ? const [] : [locationId]),
      permissions: permissions,
      rights: rights,
    );
  }
}

class Product {
  final int id;
  final String name;
  final String? barcode;
  final double sellPrice;
  final double costPrice;
  final int reorderLevel;

  Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.sellPrice,
    required this.costPrice,
    required this.reorderLevel,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: _toInt(j['id']),
        name: (j['name'] ?? '').toString(),
        barcode: _toNullableString(j['barcode']),
        sellPrice: _toDouble(j['sell_price']),
        costPrice: _toDouble(j['cost_price']),
        reorderLevel: _toInt(j['reorder_level']),
      );

  Map<String, dynamic> toDb() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'sell_price': sellPrice,
        'cost_price': costPrice,
        'reorder_level': reorderLevel,
      };

  factory Product.fromDb(Map<String, dynamic> r) => Product(
        id: _toInt(r['id']),
        name: (r['name'] ?? '').toString(),
        barcode: _toNullableString(r['barcode']),
        sellPrice: _toDouble(r['sell_price']),
        costPrice: _toDouble(r['cost_price']),
        reorderLevel: _toInt(r['reorder_level']),
      );
}

class CartItem {
  final Product product;
  int qty;
  CartItem({required this.product, required this.qty});

  double get lineTotal => product.sellPrice * qty;
}

class Transfer {
  final int id;
  final String status;
  final int fromLocationId;
  final int toLocationId;
  final String fromName;
  final String toName;
  final String createdAt;

  Transfer({
    required this.id,
    required this.status,
    required this.fromLocationId,
    required this.toLocationId,
    required this.fromName,
    required this.toName,
    required this.createdAt,
  });

  factory Transfer.fromJson(Map<String, dynamic> j) => Transfer(
        id: _toInt(j['id']),
        status: (j['status'] ?? '').toString(),
        fromLocationId: _toInt(j['from_location_id']),
        toLocationId: _toInt(j['to_location_id']),
        fromName: (j['from_name'] ?? '').toString(),
        toName: (j['to_name'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
      );
}

class TransferItem {
  final int productId;
  final String productName;
  final int qtySent;
  final int qtyReceived;

  TransferItem({
    required this.productId,
    required this.productName,
    required this.qtySent,
    required this.qtyReceived,
  });

  factory TransferItem.fromJson(Map<String, dynamic> j) => TransferItem(
        productId: _toInt(j['product_id']),
        productName: (j['product_name'] ?? '').toString(),
        qtySent: _toInt(j['qty_sent']),
        qtyReceived: _toInt(j['qty_received']),
      );
}

class StockRow {
  final int productId;
  final String name;
  final String? barcode;
  final int onHand;
  final int reorderLevel;

  StockRow({
    required this.productId,
    required this.name,
    required this.barcode,
    required this.onHand,
    required this.reorderLevel,
  });

  factory StockRow.fromJson(Map<String, dynamic> j) => StockRow(
        productId: _toInt(j['product_id']),
        name: (j['name'] ?? '').toString(),
        barcode: _toNullableString(j['barcode']),
        onHand: _toInt(j['on_hand']),
        reorderLevel: _toInt(j['reorder_level']),
      );
}

class ReportSummary {
  final String dateFrom;
  final String dateTo;
  final double totalSales;
  final int salesCount;
  final double cogs;
  final double grossProfit;
  final double expenses;
  final double netProfit;

  // Day sessions (Start/End Day)
  final bool daySessionsInstalled;
  final String? daySessionsError;
  final int? daySessionsTotal;
  final int? daySessionsOpen;
  final int? daySessionsClosed;
  final double? startCash;
  final double? closingCash;
  final double? varianceCash;
  final int negativeStockCount;
  final int lowStockCount;
  final List<Map<String, dynamic>> topProfit;
  final List<Map<String, dynamic>> topQty;
  final double refundsTotal;
  final int refundsCount;
  final double discountsTotal;

  ReportSummary({
    required this.dateFrom,
    required this.dateTo,
    required this.totalSales,
    required this.salesCount,
    required this.cogs,
    required this.grossProfit,
    required this.expenses,
    required this.netProfit,
    this.daySessionsInstalled = false,
    this.daySessionsError,
    this.daySessionsTotal,
    this.daySessionsOpen,
    this.daySessionsClosed,
    this.startCash,
    this.closingCash,
    this.varianceCash,
    required this.negativeStockCount,
    required this.lowStockCount,
    required this.topProfit,
    required this.topQty,
    this.refundsTotal = 0.0,
    this.refundsCount = 0,
    this.discountsTotal = 0.0,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
        dateFrom: (j['date_from'] ?? '').toString(),
        dateTo: (j['date_to'] ?? '').toString(),
        totalSales: _toDouble(j['total_sales']),
        salesCount: _toInt(j['sales_count']),
        cogs: _toDouble(j['cogs']),
        grossProfit: _toDouble(j['gross_profit']),
        expenses: _toDouble(j['expenses']),
        netProfit: _toDouble(j['net_profit']),

        daySessionsInstalled: j['day_sessions_installed'] == true,
        daySessionsError: j['day_sessions_error']?.toString(),
        daySessionsTotal: _toNullableInt(j['day_sessions_total']),
        daySessionsOpen: _toNullableInt(j['day_sessions_open']),
        daySessionsClosed: _toNullableInt(j['day_sessions_closed']),
        startCash: _toNullableDouble(j['start_cash']),
        closingCash: _toNullableDouble(j['closing_cash']),
        varianceCash: _toNullableDouble(j['variance_cash']),

        negativeStockCount: _toInt(j['negative_stock_count']),
        lowStockCount: _toInt(j['low_stock_count']),
        topProfit: ((j['top_products_by_profit'] as List<dynamic>?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        topQty: ((j['top_products_by_qty'] as List<dynamic>?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        refundsTotal: _toDouble(j['refunds_total']),
        refundsCount: _toInt(j['refunds_count']),
        discountsTotal: _toDouble(j['discounts_total']),
      );
}

// ────────────────────────────────────────────────────────────
// Sale lookup models (for refund flow)
// ────────────────────────────────────────────────────────────
class SaleDetail {
  final int id;
  final String saleNumber;
  final int locationId;
  final String locationName;
  final double subtotal;
  final double total;
  final String discountType;
  final double discountAmount;
  final double refundedTotal;
  final String createdAt;
  final String cashierName;
  final List<SaleItem> items;

  SaleDetail({
    required this.id,
    required this.saleNumber,
    required this.locationId,
    required this.locationName,
    required this.subtotal,
    required this.total,
    required this.discountType,
    required this.discountAmount,
    required this.refundedTotal,
    required this.createdAt,
    required this.cashierName,
    this.items = const [],
  });

  factory SaleDetail.fromJson(Map<String, dynamic> j) => SaleDetail(
        id: _toInt(j['id']),
        saleNumber: (j['sale_number'] ?? '').toString(),
        locationId: _toInt(j['location_id']),
        locationName: (j['location_name'] ?? '').toString(),
        subtotal: _toDouble(j['subtotal']),
        total: _toDouble(j['total']),
        discountType: (j['discount_type'] ?? 'none').toString(),
        discountAmount: _toDouble(j['discount_amount']),
        refundedTotal: _toDouble(j['refunded_total']),
        createdAt: (j['created_at'] ?? '').toString(),
        cashierName: (j['cashier_name'] ?? '').toString(),
        items: ((j['items'] as List<dynamic>?) ?? []).map((e) => SaleItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class SaleItem {
  final int id;
  final int productId;
  final String productName;
  final int qty;
  final double unitPrice;
  final double lineTotal;
  final int refundedQty;

  SaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
    required this.refundedQty,
  });

  int get availableForRefund => qty - refundedQty;

  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(
        id: _toInt(j['id']),
        productId: _toInt(j['product_id']),
        productName: (j['product_name'] ?? '').toString(),
        qty: _toInt(j['qty']),
        unitPrice: _toDouble(j['unit_price']),
        lineTotal: _toDouble(j['line_total']),
        refundedQty: _toInt(j['refunded_qty']),
      );
}

class Refund {
  final int id;
  final String refundNumber;
  final int saleId;
  final String? saleNumber;
  final String locationName;
  final double totalAmount;
  final String? reason;
  final String refundedBy;
  final String createdAt;
  final int itemCount;

  Refund({
    required this.id,
    required this.refundNumber,
    required this.saleId,
    this.saleNumber,
    required this.locationName,
    required this.totalAmount,
    this.reason,
    required this.refundedBy,
    required this.createdAt,
    this.itemCount = 0,
  });

  factory Refund.fromJson(Map<String, dynamic> j) => Refund(
        id: _toInt(j['id']),
        refundNumber: (j['refund_number'] ?? '').toString(),
        saleId: _toInt(j['sale_id']),
        saleNumber: _toNullableString(j['sale_number']),
        locationName: (j['location_name'] ?? '').toString(),
        totalAmount: _toDouble(j['total_amount']),
        reason: _toNullableString(j['reason']),
        refundedBy: (j['refunded_by'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        itemCount: _toInt(j['item_count']),
      );
}

class RefundItem {
  final int id;
  final int productId;
  final String productName;
  final int qty;
  final double unitPrice;
  final double lineTotal;

  RefundItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory RefundItem.fromJson(Map<String, dynamic> j) => RefundItem(
        id: _toInt(j['id']),
        productId: _toInt(j['product_id']),
        productName: (j['product_name'] ?? '').toString(),
        qty: _toInt(j['qty']),
        unitPrice: _toDouble(j['unit_price']),
        lineTotal: _toDouble(j['line_total']),
      );
}

class LowStockItem {
  final int id;
  final String name;
  final String? barcode;
  final int reorderLevel;
  final int onHand;
  final String locationName;

  LowStockItem({
    required this.id,
    required this.name,
    this.barcode,
    required this.reorderLevel,
    required this.onHand,
    required this.locationName,
  });

  factory LowStockItem.fromJson(Map<String, dynamic> j) => LowStockItem(
        id: _toInt(j['id']),
        name: (j['name'] ?? '').toString(),
        barcode: _toNullableString(j['barcode']),
        reorderLevel: _toInt(j['reorder_level']),
        onHand: _toInt(j['on_hand']),
        locationName: (j['location_name'] ?? '').toString(),
      );
}

// ────────────────────────────────────────────────────────────
// Customer model
// ────────────────────────────────────────────────────────────
class Customer {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final int loyaltyPoints;
  final double totalSpent;
  final int visitCount;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.loyaltyPoints = 0,
    this.totalSpent = 0.0,
    this.visitCount = 0,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: _toInt(j['id']),
        name: (j['name'] ?? '').toString(),
        phone: _toNullableString(j['phone']),
        email: _toNullableString(j['email']),
        address: _toNullableString(j['address']),
        loyaltyPoints: _toInt(j['loyalty_points']),
        totalSpent: _toDouble(j['total_spent']),
        visitCount: _toInt(j['visit_count']),
      );
}

// ────────────────────────────────────────────────────────────
// Category model
// ────────────────────────────────────────────────────────────
class ProductCategory {
  final int id;
  final String name;
  final int? parentId;
  final int sortOrder;
  final int productCount;

  ProductCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
    this.productCount = 0,
  });

  factory ProductCategory.fromJson(Map<String, dynamic> j) => ProductCategory(
        id: _toInt(j['id']),
        name: (j['name'] ?? '').toString(),
        parentId: _toNullableInt(j['parent_id']),
        sortOrder: _toInt(j['sort_order']),
        productCount: _toInt(j['product_count']),
      );
}

// ────────────────────────────────────────────────────────────
// Supplier model
// ────────────────────────────────────────────────────────────
class Supplier {
  final int id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;

  Supplier({
    required this.id,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
  });

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: _toInt(j['id']),
        name: (j['name'] ?? '').toString(),
        contactPerson: _toNullableString(j['contact_person']),
        phone: _toNullableString(j['phone']),
        email: _toNullableString(j['email']),
        address: _toNullableString(j['address']),
      );
}

// ────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────
// Parked cart model
// ────────────────────────────────────────────────────────────
class ParkedCart {
  final int id;
  final String? label;
  final int? customerId;
  final int itemCount;
  final double total;
  final String parkedAt;

  ParkedCart({
    required this.id,
    this.label,
    this.customerId,
    this.itemCount = 0,
    this.total = 0.0,
    required this.parkedAt,
  });

  factory ParkedCart.fromJson(Map<String, dynamic> j) => ParkedCart(
        id: _toInt(j['id']),
        label: _toNullableString(j['label']),
        customerId: _toNullableInt(j['customer_id']),
        itemCount: _toInt(j['item_count']),
        total: _toDouble(j['total']),
        parkedAt: (j['parked_at'] ?? '').toString(),
      );
}
