import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../widgets/mobile_ui.dart';

int _adminInt(dynamic value) => int.tryParse('${value ?? ''}') ?? 0;

List<Map<String, dynamic>> _adminRows(List? rows) {
  final list = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final row in rows ?? const []) {
    if (row is! Map) continue;
    final map = Map<String, dynamic>.from(row);
    final id = map['id']?.toString().trim();
    final key = (id != null && id.isNotEmpty) ? 'id:$id' : 'row:${map.toString()}';
    if (seen.add(key)) {
      list.add(map);
    }
  }
  return list;
}

int? _adminSafeNullableInt(int? value, Iterable<int?> allowedValues) {
  for (final allowed in allowedValues) {
    if (allowed == value) return value;
  }
  return null;
}

List<Map<String, dynamic>> _adminPositiveIdRows(List? rows) {
  final out = <Map<String, dynamic>>[];
  final seen = <int>{};
  for (final row in _adminRows(rows)) {
    final id = _adminInt(row['id']);
    if (id > 0 && seen.add(id)) {
      out.add(row);
    }
  }
  return out;
}

Set<int> _adminIntSet(dynamic value, [int? fallback]) {
  final out = <int>{};
  if (value is List) {
    for (final item in value) {
      final id = _adminInt(item);
      if (id > 0) out.add(id);
    }
  }
  if (out.isEmpty && fallback != null && fallback > 0) {
    out.add(fallback);
  }
  return out;
}

String _adminBaseRole(dynamic value) {
  final role = '${value ?? 'TELLER'}'.toUpperCase().trim();
  switch (role) {
    case 'SUPERADMIN':
      return 'TENANT_ADMIN';
    case 'TENANT_ADMIN':
    case 'SHOP_ADMIN':
    case 'SUPERVISOR':
    case 'TELLER':
      return role;
    default:
      return 'TELLER';
  }
}

Color _adminGroupColor(String group) {
  switch (group) {
    case 'Administration':
      return const Color(0xFF8E0000);
    case 'Bale Movement':
      return const Color(0xFF6D4C41);
    case 'Stock':
      return const Color(0xFF1565C0);
    case 'Pricing':
      return const Color(0xFF00838F);
    case 'Communication':
      return const Color(0xFF00897B);
    case 'Sales':
      return const Color(0xFF2E7D32);
    case 'Bales':
      return const Color(0xFFB26A00);
    case 'Reports':
      return const Color(0xFFE31B23);
    case 'Shift':
      return const Color(0xFFEF6C00);
    case 'Prepayments':
      return const Color(0xFF795548);
    default:
      return const Color(0xFF546E7A);
  }
}

IconData _adminGroupIcon(String group) {
  switch (group) {
    case 'Administration':
      return Icons.admin_panel_settings_rounded;
    case 'Bale Movement':
      return Icons.route_rounded;
    case 'Stock':
      return Icons.inventory_2_rounded;
    case 'Pricing':
      return Icons.sell_rounded;
    case 'Communication':
      return Icons.campaign_rounded;
    case 'Sales':
      return Icons.attach_money_rounded;
    case 'Bales':
      return Icons.category_rounded;
    case 'Reports':
      return Icons.bar_chart_rounded;
    case 'Shift':
      return Icons.lock_clock_rounded;
    case 'Prepayments':
      return Icons.receipt_long_rounded;
    default:
      return Icons.tune_rounded;
  }
}

Color _adminRoleColor(String role) {
  switch (_adminBaseRole(role)) {
    case 'TENANT_ADMIN':
      return const Color(0xFF8E0000);
    case 'SHOP_ADMIN':
      return const Color(0xFFAD1457);
    case 'SUPERVISOR':
      return const Color(0xFF1565C0);
    case 'TELLER':
      return const Color(0xFF2E7D32);
    default:
      return const Color(0xFF546E7A);
  }
}

IconData _adminRoleIcon(String role) {
  switch (_adminBaseRole(role)) {
    case 'TENANT_ADMIN':
      return Icons.workspace_premium_rounded;
    case 'SHOP_ADMIN':
      return Icons.verified_user_rounded;
    case 'SUPERVISOR':
      return Icons.support_agent_rounded;
    case 'TELLER':
      return Icons.point_of_sale_rounded;
    default:
      return Icons.person_rounded;
  }
}

class _StoreAccessEditor extends StatelessWidget {
  final List<Map<String, dynamic>> locations;
  final Set<int> selectedIds;
  final int? defaultLocationId;
  final ValueChanged<int> onToggle;
  final ValueChanged<int?> onDefaultChanged;

  const _StoreAccessEditor({
    required this.locations,
    required this.selectedIds,
    required this.defaultLocationId,
    required this.onToggle,
    required this.onDefaultChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedRows = locations
        .where((row) => selectedIds.contains(_adminInt(row['id'])))
        .toList();
    final safeDefault = selectedRows.any((row) => _adminInt(row['id']) == defaultLocationId)
        ? defaultLocationId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Assigned stores',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: locations
              .map(
                (row) => FilterChip(
                  label: Text('${row['name']}'),
                  selected: selectedIds.contains(_adminInt(row['id'])),
                  onSelected: (_) => onToggle(_adminInt(row['id'])),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Text(
          selectedIds.isEmpty
              ? 'No stores selected means this user can access all stores available to their role.'
              : 'Choose the default store used first in shift, sales, and stock screens.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int?>(
          value: safeDefault,
          isExpanded: true,
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Use first assigned store'),
            ),
            ...selectedRows.map(
              (row) => DropdownMenuItem<int?>(
                value: _adminInt(row['id']),
                child: Text('${row['name']}'),
              ),
            ),
          ],
          onChanged: onDefaultChanged,
          decoration: const InputDecoration(labelText: 'Default store'),
        ),
      ],
    );
  }
}

class AdminControlScreen extends StatefulWidget {
  final AppState appState;
  const AdminControlScreen({super.key, required this.appState});

  @override
  State<AdminControlScreen> createState() => _AdminControlScreenState();
}

class _AdminControlScreenState extends State<AdminControlScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  Map<String, dynamic>? _dashboard;
  String? _loadWarning;

  ApiClient get _api => ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);

  @override
  void initState() {
    super.initState();
    _search.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_handleSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ApiClient.friendlyError(error))),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _dashboard = await _api.getAdminControl();
      _loadWarning = null;
    } catch (e) {
      final warning = e.toString().replaceFirst('Exception: ', '');
      final usersResult = await _safeRows(() => _api.getUsers());
      final rolesResult = await _safeRows(() => _api.getRoleProfiles());
      final registrationsResult = await _safeRows(() => _api.getRegistrationRequests());
      final locationsResult = await _safeRows(() async {
        final rows = await _api.getLocations();
        return rows
            .map((item) => {
                  'id': item.id,
                  'name': item.name,
                  'type': item.type,
                })
            .toList();
      });

      _dashboard = {
        'users': usersResult.rows,
        'roles': rolesResult.rows,
        'registrations': registrationsResult.rows,
        'locations': locationsResult.rows,
      };

      final details = <String>[
        if (warning.isNotEmpty) warning,
        if (usersResult.error != null) 'Users: ${usersResult.error}',
        if (rolesResult.error != null) 'Roles: ${rolesResult.error}',
        if (registrationsResult.error != null) 'Registrations: ${registrationsResult.error}',
        if (locationsResult.error != null) 'Stores: ${locationsResult.error}',
      ];
      _loadWarning = details.isEmpty ? null : details.join('\n');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<({List<Map<String, dynamic>> rows, String? error})> _safeRows(
    Future<List<Map<String, dynamic>>> Function() loader,
  ) async {
    try {
      final rows = await loader();
      return (rows: rows, error: null);
    } catch (e) {
      return (
        rows: const <Map<String, dynamic>>[],
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _addUser() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final roles = _adminPositiveIdRows((_dashboard?['roles'] as List?) ?? const []);
    final locations = _adminRows((_dashboard?['locations'] as List?) ?? const []);
    final roleIds = [null, ...roles.map((row) => _adminInt(row['id']))];
    String role = _adminBaseRole('TELLER');
    int? roleProfileId;
    final selectedLocationIds = <int>{};
    int? locationId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          var saving = false;
          String? formError;
          return StatefulBuilder(
            builder: (ctx2, setInnerState) => AlertDialog(
              scrollable: true,
              title: const Text('Add User'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (formError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          formError!,
                          style: const TextStyle(
                            color: Color(0xFFB71C1C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: name,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: username,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: email,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: password,
                      enabled: !saving,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Temporary password'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: role,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'TENANT_ADMIN', child: Text('Admin')),
                        DropdownMenuItem(value: 'SHOP_ADMIN', child: Text('Admin 2')),
                        DropdownMenuItem(value: 'SUPERVISOR', child: Text('Supervisor')),
                        DropdownMenuItem(value: 'TELLER', child: Text('Cashier')),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setInnerState(() => role = value ?? 'TELLER'),
                      decoration: const InputDecoration(labelText: 'Base role'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      value: _adminSafeNullableInt(roleProfileId, roleIds),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('No named role')),
                        ...roles.map((row) => DropdownMenuItem<int?>(
                              value: _adminInt(row['id']),
                              child: Text('${row['name']}'),
                            )),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setInnerState(() => roleProfileId = value),
                      decoration: const InputDecoration(labelText: 'Named role'),
                    ),
                    const SizedBox(height: 10),
                    _StoreAccessEditor(
                      locations: locations.map((row) => Map<String, dynamic>.from(row)).toList(),
                      selectedIds: selectedLocationIds,
                      defaultLocationId: locationId,
                      onToggle: (id) {
                        setInnerState(() {
                          if (selectedLocationIds.contains(id)) {
                            selectedLocationIds.remove(id);
                            if (locationId == id) {
                              locationId = selectedLocationIds.isEmpty ? null : selectedLocationIds.first;
                            }
                          } else {
                            selectedLocationIds.add(id);
                            locationId ??= id;
                          }
                        });
                      },
                      onDefaultChanged: (value) => setInnerState(() => locationId = value),
                    ),
                    if (saving) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx2),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final trimmedName = name.text.trim();
                          final trimmedEmail = email.text.trim();
                          final trimmedPassword = password.text.trim();
                          if (trimmedName.isEmpty || trimmedEmail.isEmpty || trimmedPassword.isEmpty) {
                            setInnerState(() => formError = 'Name, email, and temporary password are required.');
                            return;
                          }
                          if (trimmedPassword.length < 8) {
                            setInnerState(() => formError = 'Temporary passwords must be at least 8 characters. Update the password and try again.');
                            return;
                          }
                          setInnerState(() {
                            formError = null;
                            saving = true;
                          });
                          try {
                            await _api.createUser({
                              'name': trimmedName,
                              'username': username.text.trim(),
                              'email': trimmedEmail,
                              'password': password.text,
                              'role': role,
                              'role_profile_id': roleProfileId,
                              'location_id': locationId,
                              'location_ids': selectedLocationIds.toList(),
                            });
                            if (!ctx2.mounted) return;
                            Navigator.pop(ctx2);
                            await _load();
                          } catch (e) {
                            if (!ctx2.mounted) return;
                            setInnerState(() {
                              formError = e.toString().replaceFirst('Exception: ', '');
                              saving = false;
                            });
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _manageRole([Map? role]) async {
    final name = TextEditingController(text: '${role?['name'] ?? ''}');
    String baseRole = _adminBaseRole(role?['base_role']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(role == null ? 'Add Role' : 'Edit Role'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Role name')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: baseRole,
                items: const [
                  DropdownMenuItem(value: 'TENANT_ADMIN', child: Text('Admin')),
                  DropdownMenuItem(value: 'SHOP_ADMIN', child: Text('Admin 2')),
                  DropdownMenuItem(value: 'SUPERVISOR', child: Text('Supervisor')),
                  DropdownMenuItem(value: 'TELLER', child: Text('Cashier')),
                ],
                onChanged: (value) => baseRole = value ?? 'TELLER',
                decoration: const InputDecoration(labelText: 'Base role'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.saveRoleProfile({'name': name.text.trim(), 'base_role': baseRole, 'active': 1}, id: role == null ? null : int.tryParse('${role['id']}'));
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _approveRegistration(Map row) async {
    final roles = _adminPositiveIdRows((_dashboard?['roles'] as List?) ?? const []);
    final locations = _adminRows((_dashboard?['locations'] as List?) ?? const []);
    final roleIds = [null, ...roles.map((item) => _adminInt(item['id']))];
    String role = _adminBaseRole('TELLER');
    int? roleProfileId;
    final selectedLocationIds = <int>{};
    int? locationId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Approve ${row['name'] ?? ''}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: role,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'TENANT_ADMIN', child: Text('Admin')),
                    DropdownMenuItem(value: 'SHOP_ADMIN', child: Text('Admin 2')),
                    DropdownMenuItem(value: 'SUPERVISOR', child: Text('Supervisor')),
                    DropdownMenuItem(value: 'TELLER', child: Text('Cashier')),
                  ],
                  onChanged: (value) => setDialogState(() => role = value ?? 'TELLER'),
                  decoration: const InputDecoration(labelText: 'Base role'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  value: _adminSafeNullableInt(roleProfileId, roleIds),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No named role')),
                    ...roles.map((item) => DropdownMenuItem<int?>(
                          value: _adminInt(item['id']),
                          child: Text('${item['name']}'),
                        )),
                  ],
                  onChanged: (value) => setDialogState(() => roleProfileId = value),
                  decoration: const InputDecoration(labelText: 'Named role'),
                ),
                const SizedBox(height: 10),
                _StoreAccessEditor(
                  locations: locations.map((row) => Map<String, dynamic>.from(row)).toList(),
                  selectedIds: selectedLocationIds,
                  defaultLocationId: locationId,
                  onToggle: (id) {
                    setDialogState(() {
                      if (selectedLocationIds.contains(id)) {
                        selectedLocationIds.remove(id);
                        if (locationId == id) {
                          locationId = selectedLocationIds.isEmpty ? null : selectedLocationIds.first;
                        }
                      } else {
                        selectedLocationIds.add(id);
                        locationId ??= id;
                      }
                    });
                  },
                  onDefaultChanged: (value) => setDialogState(() => locationId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.approveRegistration(int.tryParse('${row['id']}') ?? 0, {
        'role': role,
        'role_profile_id': roleProfileId,
        'location_id': locationId,
        'location_ids': selectedLocationIds.toList(),
      });
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _editUser(Map row) async {
    final userId = int.tryParse('${row['id']}') ?? 0;
    if (userId <= 0) return;
    final access = await _api.getUserAccess(userId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _UserAccessDialog(
        api: _api,
        access: access,
        onSaved: _load,
      ),
    );
  }

  Future<void> _deleteUser(Map row) async {
    final userId = int.tryParse('${row['id']}') ?? 0;
    if (userId <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete ${row['name'] ?? 'this user'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE31B23),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteAdminUser(userId);
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = (((_dashboard?['users'] as List?) ?? const [])).cast<Map>();
    final roles = (((_dashboard?['roles'] as List?) ?? const [])).cast<Map>();
    final registrations = (((_dashboard?['registrations'] as List?) ?? const [])).cast<Map>();
    final filteredUsers = users.where((row) {
      final q = _search.text.trim().toLowerCase();
      if (q.isEmpty) return true;
      final hay = '${row['name'] ?? ''} ${row['email'] ?? ''} ${row['effective_role_name'] ?? row['display_role'] ?? row['role'] ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();

    return MobilePageScaffold(
      title: 'Admin Control',
      subtitle: 'Add users, change roles, approve registrations, and assign permissions.',
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _addUser,
        backgroundColor: const Color(0xFFE31B23),
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadWarning != null && _loadWarning!.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _loadWarning!,
                style: const TextStyle(
                  color: Color(0xFF9A3412),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          MobileSectionCard(
            icon: Icons.search_rounded,
            title: 'Find User',
            subtitle: 'Search by name, email, or role label.',
            accentColor: const Color(0xFF455A64),
            child: MobileSearchField(
              controller: _search,
              hintText: 'Search users',
              onSearch: () => setState(() {}),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            MobileSectionCard(
              icon: Icons.pending_actions_rounded,
              title: 'Pending Registrations',
              subtitle: 'Approve or reject account requests from the login registration page.',
              accentColor: const Color(0xFFEF6C00),
              child: Column(
                children: registrations.isEmpty
                    ? [const Text('No pending registrations.')]
                    : registrations.map((row) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9F6F3),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${row['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                      Text('${row['email'] ?? '-'}'),
                                      const Text('Awaiting admin role and store assignment'),
                                    ],
                                  ),
                                ),
                                FilledButton.tonal(
                                  onPressed: () => _approveRegistration(row),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFE8F5E9),
                                    foregroundColor: const Color(0xFF2E7D32),
                                  ),
                                  child: const Text('Approve'),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () async {
                                    try {
                                      await _api.rejectRegistration(int.tryParse('${row['id']}') ?? 0);
                                      _load();
                                    } catch (e) {
                                      _showError(e);
                                    }
                                  },
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ],
                            ),
                          ),
                        )).toList(),
              ),
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.badge_rounded,
              title: 'Role Management',
              subtitle: 'Named role labels that sit on top of the base system roles.',
              accentColor: const Color(0xFF8E0000),
              trailing: IconButton(onPressed: () => _manageRole(), icon: const Icon(Icons.add_rounded)),
              child: Column(
                children: roles.map((row) => MobileActionTile(
                      icon: _adminRoleIcon(row['base_role']),
                      accentColor: _adminRoleColor(row['base_role']),
                      title: '${row['name'] ?? '-'}',
                      subtitle: 'Base role: ${row['base_role'] ?? '-'} | Users: ${row['user_count'] ?? 0}',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: () => _manageRole(row), icon: const Icon(Icons.edit_rounded)),
                          IconButton(
                            onPressed: () async {
                              try {
                                await _api.deleteRoleProfile(int.tryParse('${row['id']}') ?? 0);
                                _load();
                              } catch (e) {
                                _showError(e);
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    )).toList(),
              ),
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.admin_panel_settings_rounded,
              title: 'Users',
              subtitle: 'Edit permissions, reset passwords, and change roles per user.',
              accentColor: const Color(0xFF1565C0),
              child: Column(
                children: filteredUsers.map((row) => MobileActionTile(
                      icon: _adminRoleIcon(row['role']),
                      accentColor: _adminRoleColor(row['role']),
                      title: '${row['name'] ?? '-'}',
                      subtitle: '${row['email'] ?? '-'} | ${row['effective_role_name'] ?? row['display_role'] ?? row['role'] ?? '-'}${('${row['location_names'] ?? ''}').trim().isNotEmpty ? ' | ${row['location_names']}' : ''}',
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _editUser(row);
                          }
                          if (value == 'delete') {
                            _deleteUser(row);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          if (int.tryParse('${row['id']}') != widget.appState.user?.id &&
                              '${row['role'] ?? ''}' != 'SUPERADMIN')
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                        ],
                      ),
                      onTap: () => _editUser(row),
                    )).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserAccessDialog extends StatefulWidget {
  final ApiClient api;
  final Map<String, dynamic> access;
  final Future<void> Function() onSaved;

  const _UserAccessDialog({
    required this.api,
    required this.access,
    required this.onSaved,
  });

  @override
  State<_UserAccessDialog> createState() => _UserAccessDialogState();
}

class _UserAccessDialogState extends State<_UserAccessDialog> {
  late final Map<String, dynamic> user;
  late final List<Map> roles;
  late final List<Map> permissions;
  late final List<Map> rights;
  late final List<Map> locations;
  late final TextEditingController name;
  late final TextEditingController username;
  late final TextEditingController email;
  late final TextEditingController displayRole;
  late final TextEditingController password;
  late String baseRole;
  int? roleProfileId;
  int? locationId;
  late Set<int> locationIds;
  late bool active;
  late Map<String, bool> permissionState;
  late Map<String, bool> rightState;
  bool saving = false;

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ApiClient.friendlyError(error))),
    );
  }

  @override
  void initState() {
    super.initState();
    user = Map<String, dynamic>.from(widget.access['user'] as Map);
    roles = _adminPositiveIdRows((widget.access['roles'] as List?) ?? const []).cast<Map>();
    permissions = ((widget.access['permissions'] as List?) ?? const []).cast<Map>();
    rights = ((widget.access['rights'] as List?) ?? const []).cast<Map>();
    locations = _adminRows((widget.access['locations'] as List?) ?? const []).cast<Map>();
    name = TextEditingController(text: '${user['name'] ?? ''}');
    username = TextEditingController(text: '${user['username'] ?? ''}');
    email = TextEditingController(text: '${user['email'] ?? ''}');
    displayRole = TextEditingController(text: '${user['display_role'] ?? ''}');
    password = TextEditingController();
    baseRole = _adminBaseRole(user['role']);
    roleProfileId = _adminSafeNullableInt(
      int.tryParse('${user['role_profile_id'] ?? ''}'),
      [null, ...roles.map((item) => _adminInt(item['id']) > 0 ? _adminInt(item['id']) : null)],
    );
    locationIds = _adminIntSet(user['location_ids'], int.tryParse('${user['location_id'] ?? ''}'));
    locationId = locationIds.isNotEmpty
        ? (locationIds.contains(int.tryParse('${user['location_id'] ?? ''}'))
            ? int.tryParse('${user['location_id'] ?? ''}')
            : locationIds.first)
        : null;
    active = '${user['active']}' == '1';
    permissionState = {for (final item in permissions) '${item['key']}': '${item['allowed']}' == '1'};
    rightState = {for (final item in rights) '${item['key']}': '${item['enabled']}' == '1'};
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.api.saveUserAccess(int.tryParse('${user['id']}') ?? 0, {
        'name': name.text.trim(),
        'username': username.text.trim(),
        'email': email.text.trim(),
        'role': baseRole,
        'display_role': displayRole.text.trim(),
        'role_profile_id': roleProfileId,
        'location_id': locationId,
        'location_ids': locationIds.toList(),
        'active': active ? 1 : 0,
        'new_password': password.text,
        'permissions': permissionState.map((key, value) => MapEntry(key, value ? 1 : 0)),
        'rights': rightState.map((key, value) => MapEntry(key, value ? 1 : 0)),
      });
      await widget.onSaved();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissionGroups = <String, List<Map>>{};
    for (final item in permissions) {
      final group = '${item['group'] ?? 'Other'}';
      permissionGroups.putIfAbsent(group, () => <Map>[]).add(item);
    }
    final rightGroups = <String, List<Map>>{};
    for (final item in rights) {
      final group = '${item['group'] ?? 'Other Rights'}';
      rightGroups.putIfAbsent(group, () => <Map>[]).add(item);
    }

    return AlertDialog(
      scrollable: true,
      title: Text('Manage Access for ${user['name'] ?? ''}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')),
            const SizedBox(height: 10),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: baseRole,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'TENANT_ADMIN', child: Text('Admin')),
                DropdownMenuItem(value: 'SHOP_ADMIN', child: Text('Admin 2')),
                DropdownMenuItem(value: 'SUPERVISOR', child: Text('Supervisor')),
                DropdownMenuItem(value: 'TELLER', child: Text('Cashier')),
              ],
              onChanged: (value) => setState(() => baseRole = value ?? 'TELLER'),
              decoration: const InputDecoration(labelText: 'Role'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              value: _adminSafeNullableInt(
                roleProfileId,
                [null, ...roles.map((item) => _adminInt(item['id']) > 0 ? _adminInt(item['id']) : null)],
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('No named role')),
                ...roles.map((item) => DropdownMenuItem<int?>(
                      value: _adminInt(item['id']) > 0 ? _adminInt(item['id']) : null,
                      child: Text('${item['name']}'),
                    )),
              ],
              onChanged: (value) => setState(() => roleProfileId = value),
              decoration: const InputDecoration(labelText: 'Named role'),
            ),
            const SizedBox(height: 10),
            TextField(controller: displayRole, decoration: const InputDecoration(labelText: 'Display role')),
            const SizedBox(height: 10),
            _StoreAccessEditor(
              locations: locations.map((row) => Map<String, dynamic>.from(row)).toList(),
              selectedIds: locationIds,
              defaultLocationId: locationId,
              onToggle: (id) {
                setState(() {
                  if (locationIds.contains(id)) {
                    locationIds.remove(id);
                    if (locationId == id) {
                      locationId = locationIds.isEmpty ? null : locationIds.first;
                    }
                  } else {
                    locationIds.add(id);
                    locationId ??= id;
                  }
                });
              },
              onDefaultChanged: (value) => setState(() => locationId = value),
            ),
            const SizedBox(height: 10),
            TextField(controller: password, decoration: const InputDecoration(labelText: 'Reset password')),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              value: active,
              onChanged: (value) => setState(() => active = value),
              title: const Text('Active'),
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Permissions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            ...permissionGroups.entries.map((entry) {
              final color = _adminGroupColor(entry.key);
              final icon = _adminGroupIcon(entry.key);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withOpacity(0.14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: color.withOpacity(0.14),
                          foregroundColor: color,
                          child: Icon(icon, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...entry.value.map((item) {
                      final key = '${item['key']}';
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: color,
                        value: permissionState[key] ?? false,
                        onChanged: (value) => setState(() => permissionState[key] = value == true),
                        title: Text('${item['label']}'),
                        subtitle: Text('${item['key']}'),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                  ],
                ),
              );
            }),
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Other Rights', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            ...rightGroups.entries.map((entry) {
              final color = _adminGroupColor(entry.key);
              final icon = _adminGroupIcon(entry.key);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withOpacity(0.14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: color.withOpacity(0.14),
                          foregroundColor: color,
                          child: Icon(icon, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...entry.value.map((item) {
                      final key = '${item['key']}';
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: color,
                        value: rightState[key] ?? false,
                        onChanged: (value) => setState(() => rightState[key] = value == true),
                        title: Text('${item['label']}'),
                        subtitle: Text('${item['key']}'),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: saving ? null : _save, child: const Text('Update')),
      ],
    );
  }
}
