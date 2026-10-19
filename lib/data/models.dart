import '../core/utils/date_helpers.dart';
import '../core/i18n/app_language.dart';

const List<String> kFacilityPresets = [
  'AC',
  'Fan',
  'Private bathroom',
  'Shared bathroom',
  'Water heater',
  'WiFi',
  'Bed',
  'Wardrobe',
  'Desk & chair',
  'Window',
  'Balcony',
  'Motorbike parking',
  'Car parking',
  'Shared kitchen',
  'Laundry',
  'CCTV',
];

const List<String> kPaymentMethods = ['Cash', 'Bank transfer', 'E-wallet', 'Other'];

enum RoomStatus {
  available('Available'),
  occupied('Occupied'),
  reserved('Reserved'),
  maintenance('Maintenance');

  const RoomStatus(this._key);
  final String _key;
  String get label => tr(_key);

  static RoomStatus parse(String s) => RoomStatus.values
      .firstWhere((e) => e.name == s, orElse: () => RoomStatus.available);
}

enum DepositType {
  received('Deposit received'),
  deduction('Deduction'),
  refund('Refund');

  const DepositType(this._key);
  final String _key;
  String get label => tr(_key);

  static DepositType parse(String s) => DepositType.values
      .firstWhere((e) => e.name == s, orElse: () => DepositType.received);
}

enum PaymentStatus {
  paid('Paid'),
  partial('Partial'),
  unpaid('Unpaid'),
  overdue('Overdue');

  const PaymentStatus(this._key);
  final String _key;
  String get label => tr(_key);
}

class Room {
  const Room({
    this.id,
    required this.name,
    required this.price,
    required this.status,
    this.capacity = 1,
    this.facilities = const [],
    this.notes = '',
  });

  final int? id;
  final String name;
  final int price;
  final RoomStatus status;

  /// How many tenants can live in this room at the same time.
  final int capacity;
  final List<String> facilities;
  final String notes;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'price': price,
        'status': status.name,
        'capacity': capacity,
        'facilities': facilities.join('|'),
        'notes': notes,
      };

  factory Room.fromMap(Map<String, Object?> m) {
    final raw = m['facilities'] as String? ?? '';
    return Room(
      id: m['id'] as int?,
      name: m['name'] as String,
      price: m['price'] as int,
      status: RoomStatus.parse(m['status'] as String),
      capacity: (m['capacity'] as int?) ?? 1,
      facilities: raw.isEmpty ? <String>[] : raw.split('|'),
      notes: m['notes'] as String? ?? '',
    );
  }
}

class RoomPhoto {
  const RoomPhoto({required this.id, required this.roomId, required this.path});
  final int id;
  final int roomId;
  final String path;

  factory RoomPhoto.fromMap(Map<String, Object?> m) => RoomPhoto(
        id: m['id'] as int,
        roomId: m['room_id'] as int,
        path: m['path'] as String,
      );
}

class Tenant {
  const Tenant({
    this.id,
    required this.roomId,
    this.roomName = '',
    required this.name,
    this.phone = '',
    this.idNumber = '',
    this.idPhoto,
    this.institution = '',
    this.institutionAddress = '',
    this.homeAddress = '',
    this.emergencyName = '',
    this.emergencyRelation = '',
    this.emergencyPhone = '',
    this.emergencyAddress = '',
    required this.rentAmount,
    required this.moveInDate,
    required this.billingStart,
    this.endDate,
    this.moveOutDate,
    this.isActive = true,
    this.notes = '',
  });

  final int? id;
  final int? roomId;
  final String roomName;
  final String name;
  final String phone;
  final String idNumber;
  final String? idPhoto;
  final String institution; // school or workplace name
  final String institutionAddress;
  final String homeAddress;
  final String emergencyName;
  final String emergencyRelation;
  final String emergencyPhone;
  final String emergencyAddress;
  final int rentAmount;
  final DateTime moveInDate;
  final DateTime billingStart;
  final DateTime? endDate;
  final DateTime? moveOutDate;
  final bool isActive;
  final String notes;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'room_id': roomId,
        'room_name': roomName,
        'name': name,
        'phone': phone,
        'id_number': idNumber,
        'id_photo': idPhoto,
        'institution': institution,
        'institution_address': institutionAddress,
        'home_address': homeAddress,
        'emergency_name': emergencyName,
        'emergency_relation': emergencyRelation,
        'emergency_phone': emergencyPhone,
        'emergency_address': emergencyAddress,
        'rent_amount': rentAmount,
        'move_in_date': toDb(moveInDate),
        'billing_start': toDb(billingStart),
        'end_date': endDate == null ? null : toDb(endDate!),
        'move_out_date': moveOutDate == null ? null : toDb(moveOutDate!),
        'is_active': isActive ? 1 : 0,
        'notes': notes,
      };

  factory Tenant.fromMap(Map<String, Object?> m) => Tenant(
        id: m['id'] as int?,
        roomId: m['room_id'] as int?,
        roomName: m['room_name'] as String? ?? '',
        name: m['name'] as String,
        phone: m['phone'] as String? ?? '',
        idNumber: m['id_number'] as String? ?? '',
        idPhoto: m['id_photo'] as String?,
        institution: m['institution'] as String? ?? '',
        institutionAddress: m['institution_address'] as String? ?? '',
        homeAddress: m['home_address'] as String? ?? '',
        emergencyName: m['emergency_name'] as String? ?? '',
        emergencyRelation: m['emergency_relation'] as String? ?? '',
        emergencyPhone: m['emergency_phone'] as String? ?? '',
        emergencyAddress: m['emergency_address'] as String? ?? '',
        rentAmount: m['rent_amount'] as int,
        moveInDate: fromDb(m['move_in_date'] as String),
        billingStart: fromDb(m['billing_start'] as String),
        endDate: fromDbN(m['end_date'] as String?),
        moveOutDate: fromDbN(m['move_out_date'] as String?),
        isActive: (m['is_active'] as int? ?? 1) == 1,
        notes: m['notes'] as String? ?? '',
      );
}

/// An invoice for one billing period. [paidAmount]/[paidDate] are derived from
/// the payments table (via the charge_view SQL view).
class RentCharge {
  const RentCharge({
    required this.id,
    required this.tenantId,
    required this.dueDate,
    required this.periodEnd,
    required this.amount,
    required this.paidAmount,
    this.paidDate,
  });

  final int id;
  final int tenantId;
  final DateTime dueDate;
  final DateTime periodEnd;
  final int amount;
  final int paidAmount;
  final DateTime? paidDate;

  int get remaining {
    final r = amount - paidAmount;
    return r < 0 ? 0 : r;
  }

  PaymentStatus statusOn(DateTime today) {
    if (remaining == 0) return PaymentStatus.paid;
    if (dueDate.isBefore(today)) return PaymentStatus.overdue;
    if (paidAmount > 0) return PaymentStatus.partial;
    return PaymentStatus.unpaid;
  }

  factory RentCharge.fromMap(Map<String, Object?> m) => RentCharge(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        dueDate: fromDb(m['due_date'] as String),
        periodEnd: fromDb(m['period_end'] as String),
        amount: m['amount'] as int,
        paidAmount: (m['paid_amount'] as int?) ?? 0,
        paidDate: fromDbN(m['paid_date'] as String?),
      );
}

class ChargeView {
  const ChargeView({
    required this.charge,
    required this.tenantName,
    required this.roomName,
    required this.tenantPhone,
  });

  final RentCharge charge;
  final String tenantName;
  final String roomName;
  final String tenantPhone;

  factory ChargeView.fromMap(Map<String, Object?> m) => ChargeView(
        charge: RentCharge.fromMap(m),
        tenantName: m['tenant_name'] as String? ?? '',
        roomName: m['room_name'] as String? ?? '',
        tenantPhone: m['tenant_phone'] as String? ?? '',
      );
}

class Payment {
  const Payment({
    required this.id,
    required this.chargeId,
    required this.amount,
    required this.paidOn,
    required this.method,
    this.proofPhoto,
    this.note = '',
  });

  final int id;
  final int chargeId;
  final int amount;
  final DateTime paidOn;
  final String method;
  final String? proofPhoto;
  final String note;

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as int,
        chargeId: m['charge_id'] as int,
        amount: m['amount'] as int,
        paidOn: fromDb(m['paid_on'] as String),
        method: m['method'] as String? ?? 'Cash',
        proofPhoto: m['proof_photo'] as String?,
        note: m['note'] as String? ?? '',
      );
}

class DepositEntry {
  const DepositEntry({
    required this.id,
    required this.tenantId,
    required this.type,
    required this.amount,
    required this.date,
    this.note = '',
  });

  final int id;
  final int tenantId;
  final DepositType type;
  final int amount;
  final DateTime date;
  final String note;

  factory DepositEntry.fromMap(Map<String, Object?> m) => DepositEntry(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        type: DepositType.parse(m['type'] as String),
        amount: m['amount'] as int,
        date: fromDb(m['entry_date'] as String),
        note: m['note'] as String? ?? '',
      );
}

class RoomOverview {
  const RoomOverview({
    required this.room,
    this.tenants = const [],
    this.coverPhoto,
    this.nextDue,
  });
  final Room room;

  /// All currently active tenants living in this room (a room may hold more
  /// than one when [Room.capacity] is greater than 1).
  final List<Tenant> tenants;
  final String? coverPhoto;

  /// The soonest upcoming due date among this room's tenants, if any.
  final DateTime? nextDue;

  bool get isFull => tenants.length >= room.capacity;
  int get vacancies =>
      (room.capacity - tenants.length) < 0 ? 0 : room.capacity - tenants.length;
}

class TenantOverview {
  const TenantOverview({
    required this.tenant,
    this.nextDue,
    this.outstanding = 0,
    this.overdueCount = 0,
  });
  final Tenant tenant;
  final DateTime? nextDue;
  final int outstanding;
  final int overdueCount;
}

class KostProfile {
  const KostProfile({this.name = '', this.paymentInfo = ''});
  final String name;
  final String paymentInfo;
}
