// ─────────────────────────────────────────────────────────────────────────────
//  models/m.dart  —  Full multi-tenant model layer
// ─────────────────────────────────────────────────────────────────────────────

// ── Role Access Control ───────────────────────────────────────────────────────
// Single source of truth for what each role can do.
// Use in UI:  if (RoleAccess.canCreateJob(user.role)) { ... }
// Use in widgets: RoleAccess.guard(user.role, RoleAccess.canCreateJob, child: widget)

class RoleAccess {
  // ── Job permissions ──────────────────────────────────────────
  static bool canCreateJob(String role)   => _any(role, ['admin','manager','reception']);
  static bool canEditJob(String role)     => _any(role, ['admin','manager','reception','technician']);
  static bool canDeleteJob(String role)   => _any(role, ['admin','manager']);
  static bool canAssignJob(String role)   => _any(role, ['admin','manager']);
  static bool canUpdateStatus(String role)=> _any(role, ['admin','manager','technician']);
  static bool canCancelJob(String role)   => _any(role, ['admin','manager']);
  static bool canReopenJob(String role)   => _any(role, ['admin','manager']);

  // ── Customer permissions ────────────────────────────────────
  static bool canViewCustomers(String role)   => _any(role, ['admin','manager','reception','technician']);
  static bool canCreateCustomer(String role)  => _any(role, ['admin','manager','reception']);
  static bool canEditCustomer(String role)    => _any(role, ['admin','manager','reception']);
  static bool canDeleteCustomer(String role)  => _any(role, ['admin','manager']);
  static bool canBlacklist(String role)       => _any(role, ['admin','manager']);
  static bool canMarkVip(String role)         => _any(role, ['admin','manager']);

  // ── Inventory permissions ───────────────────────────────────
  static bool canViewInventory(String role)   => _any(role, ['admin','manager','technician','reception']);
  static bool canCreateProduct(String role)   => _any(role, ['admin','manager']);
  static bool canEditProduct(String role)     => _any(role, ['admin','manager']);
  static bool canDeleteProduct(String role)   => _any(role, ['admin']);
  static bool canAdjustStock(String role)     => _any(role, ['admin','manager']);

  // ── Invoice / Transaction permissions ──────────────────────
  static bool canCreateInvoice(String role)   => _any(role, ['admin','manager','reception']);
  static bool canViewInvoices(String role)    => _any(role, ['admin','manager','reception','technician']);
  static bool canProcessPayment(String role)  => _any(role, ['admin','manager','reception']);
  static bool canRefund(String role)          => _any(role, ['admin','manager']);
  static bool canViewTransactions(String role)=> _any(role, ['admin','manager']);

  // ── Staff / User management ─────────────────────────────────
  static bool canViewStaff(String role)       => _any(role, ['admin','manager']);
  static bool canCreateStaff(String role)     => _any(role, ['admin']);
  static bool canEditStaff(String role)       => _any(role, ['admin']);
  static bool canDeactivateStaff(String role) => _any(role, ['admin']);
  static bool canResetPin(String role)        => _any(role, ['admin']);
  static bool canChangeRole(String role)      => _any(role, ['admin']);

  // ── Shop settings ───────────────────────────────────────────
  static bool canViewSettings(String role)    => _any(role, ['admin','manager']);
  static bool canEditSettings(String role)    => _any(role, ['admin']);
  static bool canViewBilling(String role)     => _any(role, ['admin']);

  // ── Reports / Dashboard ─────────────────────────────────────
  static bool canViewReports(String role)     => _any(role, ['admin','manager']);
  static bool canViewDashboard(String role)   => true; // all roles

  // ── Owner-only ───────────────────────────────────────────────
  static bool canTransferOwnership(String role, bool isOwner) => isOwner;
  static bool canSuspendShop(String role, bool isOwner)       => isOwner;
  static bool canDeleteShop(String role, bool isOwner)        => isOwner;

  // ── Helper ───────────────────────────────────────────────────
  static bool _any(String role, List<String> allowed) => allowed.contains(role);

  // ── Nav items visible to role ────────────────────────────────
  static List<String> visibleNavItems(String role) {
    final items = <String>['dashboard', 'jobs'];
    if (canViewCustomers(role))   items.add('customers');
    if (canViewInventory(role))   items.add('inventory');
    if (canViewInvoices(role))    items.add('invoices');
    if (canViewTransactions(role))items.add('transactions');
    if (canViewReports(role))     items.add('reports');
    if (canViewStaff(role))       items.add('staff');
    if (canViewSettings(role))    items.add('settings');
    return items;
  }
}

// ── StaffMember (used on Staff Management screen) ────────────────────────────
class StaffMember {
  final String uid;
  final String shopId;
  final String displayName;
  final String email;
  final String phone;
  final String role;
  final bool isOwner;
  final bool isActive;
  final bool biometricEnabled;
  final String specialization;
  final String pin;
  final String pinHash;
  final String lastLoginAt;
  final String createdAt;
  final String joinedAt;
  final int totalJobs;
  final int completedJobs;
  final double rating;

  StaffMember({
    required this.uid,
    required this.shopId,
    required this.displayName,
    required this.email,
    this.phone = '',
    required this.role,
    this.isOwner = false,
    this.isActive = true,
    this.biometricEnabled = false,
    this.specialization = 'General',
    this.pin = '',
    this.pinHash = '',
    this.lastLoginAt = '',
    required this.createdAt,
    this.joinedAt = '',
    this.totalJobs = 0,
    this.completedJobs = 0,
    this.rating = 5.0,
  });

  bool get canBeEdited => !isOwner;
  bool get canBeDeactivated => !isOwner;
  bool get canHaveRoleChanged => !isOwner;

  String get roleLabel {
    switch (role) {
      case 'admin':      return 'Admin';
      case 'manager':    return 'Manager';
      case 'technician': return 'Technician';
      case 'reception':  return 'Reception';
      default:           return role;
    }
  }

  StaffMember copyWith({
    String? uid, String? shopId, String? displayName, String? email,
    String? phone, String? role, bool? isOwner, bool? isActive,
    bool? biometricEnabled, String? specialization, String? pin,
    String? pinHash,
    String? lastLoginAt, String? createdAt, String? joinedAt,
    int? totalJobs, int? completedJobs, double? rating,
  }) => StaffMember(
    uid: uid ?? this.uid,
    shopId: shopId ?? this.shopId,
    displayName: displayName ?? this.displayName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    role: role ?? this.role,
    isOwner: isOwner ?? this.isOwner,
    isActive: isActive ?? this.isActive,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    specialization: specialization ?? this.specialization,
    pin: pin ?? this.pin,
    pinHash: pinHash ?? this.pinHash,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    createdAt: createdAt ?? this.createdAt,
    joinedAt: joinedAt ?? this.joinedAt,
    totalJobs: totalJobs ?? this.totalJobs,
    completedJobs: completedJobs ?? this.completedJobs,
    rating: rating ?? this.rating,
  );

  factory StaffMember.fromMap(String uid, Map<String, dynamic> data) => StaffMember(
    uid: uid,
    shopId: (data['shopId'] as String?) ?? '',
    displayName: (data['displayName'] as String?) ?? (data['name'] as String?) ?? '',
    email: (data['email'] as String?) ?? '',
    phone: (data['phone'] as String?) ?? '',
    role: (data['role'] as String?) ?? 'technician',
    isOwner: (data['isOwner'] as bool?) ?? false,
    isActive: (data['isActive'] as bool?) ?? true,
    biometricEnabled: (data['biometricEnabled'] as bool?) ?? false,
    specialization: (data['specialization'] as String?) ?? 'General',
    pin: (data['pin'] as String?) ?? '',
    pinHash: (data['pin_hash'] as String?) ?? '',
    lastLoginAt: (data['lastLoginAt'] as String?) ?? '',
    createdAt: (data['createdAt'] as String?) ?? '',
    joinedAt: (data['joinedAt'] as String?) ?? (data['createdAt'] as String?) ?? '',
    totalJobs: (data['totalJobs'] as int?) ?? 0,
    completedJobs: (data['completedJobs'] as int?) ?? 0,
    rating: (data['rating'] as num?)?.toDouble() ?? 5.0,
  );

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'shopId': shopId,
    'displayName': displayName,
    'email': email,
    'phone': phone,
    'role': role,
    'isOwner': isOwner,
    'isActive': isActive,
    'biometricEnabled': biometricEnabled,
    'specialization': specialization,
    'pin': pin,
    'lastLoginAt': lastLoginAt,
    'createdAt': createdAt,
    'joinedAt': joinedAt,
    'totalJobs': totalJobs,
    'completedJobs': completedJobs,
    'rating': rating,
  };
}

// ── Job ───────────────────────────────────────────────────────────────────────
class Job {
  String jobId;
  String jobNumber;
  String shopId;
  String customerId;
  String customerName;
  String customerPhone;
  String brand;
  String model;
  String imei;
  String color;
  String problem;
  String notes;
  String status;
  String? previousStatus;
  String? holdReason;
  String priority;
  String technicianId;
  String technicianName;
  String createdAt;
  String estimatedEndDate;
  double laborCost;
  double partsCost;
  double discountAmount;
  double taxAmount;
  double totalAmount;
  List<PartUsed> partsUsed;
  List<String> intakePhotos;
  List<String> completionPhotos;
  List<TimelineEntry> timeline;
  bool notificationSent;
  String notificationChannel;
  int reopenCount;
  String? warrantyExpiry;
  String? invoiceId;
  String updatedAt;
  // ── Payment ──────────────────────────────────────────────────
  String paymentStatus;   // 'Unpaid' | 'Paid' | 'Partial'
  String paymentMethod;   // 'Cash' | 'UPI' | 'Card' | 'Bank Transfer'
  double amountPaid;
  String? paidAt;         // ISO timestamp when payment was collected

  Job({
    required this.jobId, required this.jobNumber, required this.shopId,
    required this.customerId, required this.customerName, required this.customerPhone,
    required this.brand, required this.model,
    this.imei = '', this.color = '',
    required this.problem, this.notes = '',
    this.status = 'Checked In',
    this.previousStatus, this.holdReason,
    this.priority = 'Normal',
    this.technicianId = '', this.technicianName = 'Unassigned',
    required this.createdAt, required this.estimatedEndDate,
    this.laborCost = 0, this.partsCost = 0, this.discountAmount = 0,
    this.taxAmount = 0, this.totalAmount = 0,
    this.partsUsed = const [], this.intakePhotos = const [],
    this.completionPhotos = const [], this.timeline = const [],
    this.notificationSent = false, this.notificationChannel = 'WhatsApp',
    this.reopenCount = 0, this.warrantyExpiry, this.invoiceId,
    required this.updatedAt,
    this.paymentStatus = 'Unpaid',
    this.paymentMethod = 'Cash',
    this.amountPaid = 0.0,
    this.paidAt,
  });

  double get subtotal => laborCost + partsCost;
  bool get isOnHold    => status == 'On Hold';
  bool get isCancelled => status == 'Cancelled';
  bool get isCompleted => status == 'Completed' || status == 'Delivered';
  bool get isActive    => !isOnHold && !isCancelled && !isCompleted;
  bool get canBeReopened => isCompleted || isCancelled;

  bool get isUnderWarranty {
    if (warrantyExpiry == null) return false;
    try { return DateTime.now().isBefore(DateTime.parse(warrantyExpiry!)); }
    catch (_) { return false; }
  }

  bool get isOverdue {
    if (isCompleted || isCancelled || estimatedEndDate.isEmpty) return false;
    try { return DateTime.now().isAfter(DateTime.parse(estimatedEndDate)); }
    catch (_) { return false; }
  }

  Job copyWith({
    String? jobId, String? jobNumber, String? shopId, String? customerId,
    String? customerName, String? customerPhone, String? brand, String? model,
    String? imei, String? color, String? problem, String? notes, String? status,
    String? previousStatus, String? holdReason,
    String? priority, String? technicianId, String? technicianName,
    String? createdAt, String? estimatedEndDate, double? laborCost,
    double? partsCost, double? discountAmount, double? taxAmount,
    double? totalAmount, List<PartUsed>? partsUsed,
    List<String>? intakePhotos, List<String>? completionPhotos,
    List<TimelineEntry>? timeline, bool? notificationSent,
    String? notificationChannel, int? reopenCount,
    String? warrantyExpiry, String? invoiceId, String? updatedAt,
    String? paymentStatus, String? paymentMethod,
    double? amountPaid, String? paidAt,
  }) => Job(
    jobId: jobId ?? this.jobId, jobNumber: jobNumber ?? this.jobNumber,
    shopId: shopId ?? this.shopId, customerId: customerId ?? this.customerId,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    brand: brand ?? this.brand, model: model ?? this.model,
    imei: imei ?? this.imei, color: color ?? this.color,
    problem: problem ?? this.problem, notes: notes ?? this.notes,
    status: status ?? this.status,
    previousStatus: previousStatus ?? this.previousStatus,
    holdReason: holdReason ?? this.holdReason,
    priority: priority ?? this.priority,
    technicianId: technicianId ?? this.technicianId,
    technicianName: technicianName ?? this.technicianName,
    createdAt: createdAt ?? this.createdAt,
    estimatedEndDate: estimatedEndDate ?? this.estimatedEndDate,
    laborCost: laborCost ?? this.laborCost,
    partsCost: partsCost ?? this.partsCost,
    discountAmount: discountAmount ?? this.discountAmount,
    taxAmount: taxAmount ?? this.taxAmount,
    totalAmount: totalAmount ?? this.totalAmount,
    partsUsed: partsUsed ?? this.partsUsed,
    intakePhotos: intakePhotos ?? this.intakePhotos,
    completionPhotos: completionPhotos ?? this.completionPhotos,
    timeline: timeline ?? this.timeline,
    notificationSent: notificationSent ?? this.notificationSent,
    notificationChannel: notificationChannel ?? this.notificationChannel,
    reopenCount: reopenCount ?? this.reopenCount,
    warrantyExpiry: warrantyExpiry ?? this.warrantyExpiry,
    invoiceId: invoiceId ?? this.invoiceId,
    updatedAt: updatedAt ?? this.updatedAt,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    amountPaid: amountPaid ?? this.amountPaid,
    paidAt: paidAt ?? this.paidAt,
  );

  factory Job.fromMap(Map<String, dynamic> data) => Job(
    jobId: (data['jobId'] as String?) ?? '',
    jobNumber: (data['jobNumber'] as String?) ?? '',
    shopId: (data['shopId'] as String?) ?? '',
    customerId: (data['customerId'] as String?) ?? '',
    customerName: (data['customerName'] as String?) ?? '',
    customerPhone: (data['customerPhone'] as String?) ?? '',
    brand: (data['brand'] as String?) ?? '',
    model: (data['model'] as String?) ?? '',
    imei: (data['imei'] as String?) ?? '',
    color: (data['color'] as String?) ?? '',
    problem: (data['problem'] as String?) ?? '',
    notes: (data['notes'] as String?) ?? '',
    status: (data['status'] as String?) ?? 'Checked In',
    previousStatus: data['previousStatus'] as String?,
    holdReason: data['holdReason'] as String?,
    priority: (data['priority'] as String?) ?? 'Normal',
    technicianId: (data['technicianId'] as String?) ?? '',
    technicianName: (data['technicianName'] as String?) ?? 'Unassigned',
    createdAt: (data['createdAt'] as String?) ?? '',
    estimatedEndDate: (data['estimatedEndDate'] as String?) ?? '',
    laborCost: (data['laborCost'] as num?)?.toDouble() ?? 0,
    partsCost: (data['partsCost'] as num?)?.toDouble() ?? 0,
    discountAmount: (data['discountAmount'] as num?)?.toDouble() ?? 0,
    taxAmount: (data['taxAmount'] as num?)?.toDouble() ?? 0,
    totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0,
    partsUsed: (data['partsUsed'] as List?)?.map((p) => PartUsed(
      productId: (p['productId'] as String?) ?? '',
      name: (p['name'] as String?) ?? '',
      quantity: (p['quantity'] as int?) ?? 0,
      price: (p['price'] as num?)?.toDouble() ?? 0,
    )).toList() ?? [],
    intakePhotos: List<String>.from(data['intakePhotos'] ?? []),
    completionPhotos: List<String>.from(data['completionPhotos'] ?? []),
    timeline: (data['timeline'] as List?)?.map((t) => TimelineEntry(
      status: (t['status'] as String?) ?? '',
      time: (t['time'] as String?) ?? '',
      by: (t['by'] as String?) ?? '',
      note: (t['note'] as String?) ?? '',
      type: (t['type'] as String?) ?? 'flow',
    )).toList() ?? [],
    notificationSent: (data['notificationSent'] as bool?) ?? false,
    notificationChannel: (data['notificationChannel'] as String?) ?? 'WhatsApp',
    reopenCount: (data['reopenCount'] as int?) ?? 0,
    warrantyExpiry: data['warrantyExpiry'] as String?,
    invoiceId: data['invoiceId'] as String?,
    updatedAt: (data['updatedAt'] as String?) ?? '',
    paymentStatus: (data['paymentStatus'] as String?) ?? 'Unpaid',
    paymentMethod: (data['paymentMethod'] as String?) ?? 'Cash',
    amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0.0,
    paidAt: data['paidAt'] as String?,
  );
}

class PartUsed {
  final String productId;
  final String name;
  final int quantity;
  final double price;
  PartUsed({required this.productId, required this.name,
            required this.quantity, required this.price});
  PartUsed copyWith({String? productId, String? name, int? quantity, double? price}) =>
      PartUsed(
        productId: productId ?? this.productId, name: name ?? this.name,
        quantity: quantity ?? this.quantity, price: price ?? this.price,
      );
}

class TimelineEntry {
  final String status;
  final String time;
  final String by;
  final String note;
  final String type; // flow | note | hold | cancel | reopen
  TimelineEntry({
    required this.status, required this.time, required this.by,
    this.note = '', this.type = 'flow',
  });
}

// ── Customer ──────────────────────────────────────────────────────────────────
class Customer {
  String customerId;
  String shopId;
  String name;
  String phone;
  String email;
  String address;
  String tier;
  bool isVip;
  bool isBlacklisted;
  int points;
  int repairsCount;
  double totalSpend;
  String notes;
  String createdAt;
  String updatedAt;

  Customer({
    required this.customerId, required this.shopId, required this.name,
    required this.phone, this.email = '', this.address = '',
    this.tier = 'Bronze', this.isVip = false, this.isBlacklisted = false,
    this.points = 0, this.repairsCount = 0, this.totalSpend = 0,
    this.notes = '', required this.createdAt, required this.updatedAt,
  });

  Customer copyWith({
    String? customerId, String? shopId, String? name, String? phone,
    String? email, String? address, String? tier, bool? isVip,
    bool? isBlacklisted, int? points, int? repairsCount, double? totalSpend,
    String? notes, String? createdAt, String? updatedAt,
  }) => Customer(
    customerId: customerId ?? this.customerId, shopId: shopId ?? this.shopId,
    name: name ?? this.name, phone: phone ?? this.phone,
    email: email ?? this.email, address: address ?? this.address,
    tier: tier ?? this.tier, isVip: isVip ?? this.isVip,
    isBlacklisted: isBlacklisted ?? this.isBlacklisted,
    points: points ?? this.points, repairsCount: repairsCount ?? this.repairsCount,
    totalSpend: totalSpend ?? this.totalSpend, notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Customer.fromMap(Map<String, dynamic> data) => Customer(
    customerId: (data['customerId'] as String?) ?? '',
    shopId: (data['shopId'] as String?) ?? '',
    name: (data['name'] as String?) ?? '',
    phone: (data['phone'] as String?) ?? '',
    email: (data['email'] as String?) ?? '',
    address: (data['address'] as String?) ?? '',
    tier: (data['tier'] as String?) ?? 'Bronze',
    isVip: (data['isVip'] as bool?) ?? false,
    isBlacklisted: (data['isBlacklisted'] as bool?) ?? false,
    points: (data['points'] as int?) ?? 0,
    repairsCount: (data['repairsCount'] as int?) ?? 0,
    totalSpend: (data['totalSpend'] as num?)?.toDouble() ?? 0,
    notes: (data['notes'] as String?) ?? '',
    createdAt: (data['createdAt'] as String?) ?? '',
    updatedAt: (data['updatedAt'] as String?) ?? '',
  );
}

// ── Product ───────────────────────────────────────────────────────────────────
class Product {
  String productId;
  String shopId;
  String sku;
  String productName;
  String category;
  String brand;
  String description;
  String supplierName;
  double costPrice;
  double sellingPrice;
  int stockQty;
  int reorderLevel;
  List<Map<String, dynamic>> stockHistory;
  bool isActive;
  String imageUrl;
  String createdAt;
  String updatedAt;

  Product({
    required this.productId, required this.shopId, required this.sku,
    required this.productName, required this.category,
    this.brand = '', this.description = '', this.supplierName = '',
    required this.costPrice, required this.sellingPrice,
    required this.stockQty, required this.reorderLevel,
    this.stockHistory = const [], this.isActive = true, this.imageUrl = '',
    required this.createdAt, required this.updatedAt,
  });

  bool get isLowStock  => stockQty > 0 && stockQty <= reorderLevel;
  bool get isOutOfStock => stockQty == 0;

  Product copyWith({
    String? productId, String? shopId, String? sku, String? productName,
    String? category, String? brand, String? description, String? supplierName,
    double? costPrice, double? sellingPrice, int? stockQty, int? reorderLevel,
    List<Map<String, dynamic>>? stockHistory, bool? isActive, String? imageUrl,
    String? createdAt, String? updatedAt,
  }) => Product(
    productId: productId ?? this.productId, shopId: shopId ?? this.shopId,
    sku: sku ?? this.sku, productName: productName ?? this.productName,
    category: category ?? this.category, brand: brand ?? this.brand,
    description: description ?? this.description,
    supplierName: supplierName ?? this.supplierName,
    costPrice: costPrice ?? this.costPrice,
    sellingPrice: sellingPrice ?? this.sellingPrice,
    stockQty: stockQty ?? this.stockQty, reorderLevel: reorderLevel ?? this.reorderLevel,
    stockHistory: stockHistory ?? this.stockHistory,
    isActive: isActive ?? this.isActive, imageUrl: imageUrl ?? this.imageUrl,
    createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ── Technician ────────────────────────────────────────────────────────────────
class Technician {
  String techId;
  String shopId;
  String name;
  String phone;
  String specialization;
  int totalJobs;
  int completedJobs;
  double rating;
  bool isActive;
  String joinedAt;
  String pin;
  String role; // 'technician' | 'manager' | 'reception' | 'admin'

  Technician({
    required this.techId, required this.shopId, required this.name,
    this.phone = '', this.specialization = 'General',
    this.totalJobs = 0, this.completedJobs = 0,
    this.rating = 5.0, this.isActive = true,
    this.joinedAt = '', this.pin = '',
    this.role = 'technician',
  });

  Technician copyWith({
    String? techId, String? shopId, String? name, String? phone,
    String? specialization, int? totalJobs, int? completedJobs,
    double? rating, bool? isActive, String? joinedAt, String? pin,
    String? role,
  }) => Technician(
    techId: techId ?? this.techId, shopId: shopId ?? this.shopId,
    name: name ?? this.name, phone: phone ?? this.phone,
    specialization: specialization ?? this.specialization,
    totalJobs: totalJobs ?? this.totalJobs,
    completedJobs: completedJobs ?? this.completedJobs,
    rating: rating ?? this.rating,
    isActive: isActive ?? this.isActive,
    joinedAt: joinedAt ?? this.joinedAt,
    pin: pin ?? this.pin,
    role: role ?? this.role,
  );
}

// ── CartItem ──────────────────────────────────────────────────────────────────
class CartItem {
  final Product product;
  int qty;
  CartItem({required this.product, this.qty = 1});
}

// ── ShopSettings ──────────────────────────────────────────────────────────────
class ShopSettings {
  String shopId;
  String shopName;
  String ownerUid;       // NEW — who owns this shop
  String ownerName;
  String ownerEmail;     // NEW
  String phone;
  String email;
  String address;
  String gstNumber;
  String logoUrl;
  String invoicePrefix;
  double defaultTaxRate;
  int defaultWarrantyDays;
  bool requireIntakePhoto;
  bool requireCompletionPhoto;
  Map<String, dynamic> settings;
  String createdAt;
  String plan;
  String? planExpiresAt; // NEW — null = no expiry (free plan)
  bool isActive;         // NEW — false = shop suspended
  bool darkMode;
  final List<String> enabledPayments;
  final List<Map<String, String>> workflowStages;

  ShopSettings({
    this.shopId = '',
    this.shopName = 'My Shop',
    this.ownerUid = '',
    this.ownerName = 'Admin',
    this.ownerEmail = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.gstNumber = '',
    this.logoUrl = '',
    this.invoicePrefix = 'INV',
    this.defaultTaxRate = 18.0,
    this.defaultWarrantyDays = 30,
    this.requireIntakePhoto = false,
    this.requireCompletionPhoto = false,
    this.settings = const {},
    this.createdAt = '',
    this.plan = 'free',
    this.planExpiresAt,
    this.isActive = true,
    this.darkMode = false,
    this.enabledPayments = const ['Cash', 'UPI (GPay/PhonePe)'],
    this.workflowStages = const [
      {'icon': '📥', 'title': 'Checked In',       'desc': 'Device received at counter'},
      {'icon': '🔍', 'title': 'Diagnosed',         'desc': 'Issue identified by technician'},
      {'icon': '⏳', 'title': 'Awaiting Approval', 'desc': 'Waiting for customer quote approval'},
      {'icon': '⚙️', 'title': 'In Repair',         'desc': 'Work currently being performed'},
      {'icon': '📦', 'title': 'Awaiting Parts',    'desc': 'Waiting for spare parts to arrive'},
      {'icon': '🧪', 'title': 'Quality Check',     'desc': 'Testing device after repair'},
      {'icon': '✅', 'title': 'Ready for Pickup',  'desc': 'Customer notified, device ready'},
      {'icon': '🎉', 'title': 'Delivered',         'desc': 'Device handed over to customer'},
      {'icon': '🚫', 'title': 'Cancelled',         'desc': 'Repair cancelled or rejected'},
    ],
  });

  bool get isPlanExpired {
    if (planExpiresAt == null) return false;
    try { return DateTime.now().isAfter(DateTime.parse(planExpiresAt!)); }
    catch (_) { return false; }
  }

  List<String> get workflowStatusTitles =>
      workflowStages.map((s) => s['title'] ?? '').where((t) => t.isNotEmpty).toList();

  ShopSettings copyWith({
    String? shopId, String? shopName, String? ownerUid, String? ownerName,
    String? ownerEmail, String? phone, String? email, String? address,
    String? gstNumber, String? logoUrl, String? invoicePrefix,
    double? defaultTaxRate, int? defaultWarrantyDays,
    bool? requireIntakePhoto, bool? requireCompletionPhoto,
    Map<String, dynamic>? settings, String? createdAt,
    String? plan, String? planExpiresAt, bool? isActive, bool? darkMode,
    List<String>? enabledPayments, List<Map<String, String>>? workflowStages,
  }) => ShopSettings(
    shopId: shopId ?? this.shopId,
    shopName: shopName ?? this.shopName,
    ownerUid: ownerUid ?? this.ownerUid,
    ownerName: ownerName ?? this.ownerName,
    ownerEmail: ownerEmail ?? this.ownerEmail,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    gstNumber: gstNumber ?? this.gstNumber,
    logoUrl: logoUrl ?? this.logoUrl,
    invoicePrefix: invoicePrefix ?? this.invoicePrefix,
    defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
    defaultWarrantyDays: defaultWarrantyDays ?? this.defaultWarrantyDays,
    requireIntakePhoto: requireIntakePhoto ?? this.requireIntakePhoto,
    requireCompletionPhoto: requireCompletionPhoto ?? this.requireCompletionPhoto,
    settings: settings ?? this.settings,
    createdAt: createdAt ?? this.createdAt,
    plan: plan ?? this.plan,
    planExpiresAt: planExpiresAt ?? this.planExpiresAt,
    isActive: isActive ?? this.isActive,
    darkMode: darkMode ?? this.darkMode,
    enabledPayments: enabledPayments ?? this.enabledPayments,
    workflowStages: workflowStages ?? this.workflowStages,
  );
}

// ── SessionUser ───────────────────────────────────────────────────────────────
class SessionUser {
  final String uid;
  final String email;
  final String displayName;
  final String role;
  final String shopId;
  final String phone;
  final String pinHash;
  final bool biometricEnabled;
  final bool isActive;
  final bool isOwner;          // NEW
  final String lastLoginAt;
  final String createdAt;

  SessionUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.shopId,
    this.phone = '',
    this.pinHash = '',
    this.biometricEnabled = false,
    this.isActive = true,
    this.isOwner = false,      // NEW
    this.lastLoginAt = '',
    required this.createdAt,
  });

  // Convenience role checks
  bool get isAdmin      => role == 'admin';
  bool get isManager    => role == 'manager';
  bool get isTechnician => role == 'technician';
  bool get isReception  => role == 'reception';

  // Access helpers — delegates to RoleAccess
  bool can(bool Function(String) permission) => isActive && permission(role);
  bool get canManageStaff    => can(RoleAccess.canViewStaff);
  bool get canManageSettings => can(RoleAccess.canEditSettings);
  bool get canViewBilling    => isOwner && isActive;
}

// ── Invoice ───────────────────────────────────────────────────────────────────
class Invoice {
  String invoiceId;
  String invoiceNumber;
  String shopId;
  String? jobId;
  String customerId;
  List<Map<String, dynamic>> lineItems;
  double subtotal;
  double discount;
  double taxRate;
  double taxAmount;
  double grandTotal;
  String paymentMethod;
  String paymentStatus;
  double amountPaid;
  double balanceDue;
  String notes;
  String pdfUrl;
  String issuedAt;
  String? paidAt;

  Invoice({
    required this.invoiceId, required this.invoiceNumber, required this.shopId,
    this.jobId, required this.customerId, required this.lineItems,
    required this.subtotal, required this.discount, required this.taxRate,
    required this.taxAmount, required this.grandTotal,
    required this.paymentMethod, required this.paymentStatus,
    required this.amountPaid, required this.balanceDue,
    this.notes = '', this.pdfUrl = '',
    required this.issuedAt, this.paidAt,
  });
}
