import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../widgets/mobile_ui.dart';

class NotificationsScreen extends StatefulWidget {
  final AppState appState;
  const NotificationsScreen({super.key, required this.appState});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  int _unreadCount = 0;
  String? _loadError;

  ApiClient get _api => ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);

  String _friendlyLoadError(Object error) => ApiClient.friendlyError(
        error,
        fallback: 'Check your internet connection and tap Reload to try again.',
      );

  bool get _canSend {
    final role = (widget.appState.user?.role ?? 'TELLER').toUpperCase();
    return const ['SUPERVISOR', 'SHOP_ADMIN', 'TENANT_ADMIN', 'SUPERADMIN'].contains(role);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getNotifications();
      _rows = ((data['notifications'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _unreadCount = int.tryParse('${data['unread_count'] ?? 0}') ?? 0;
      _loadError = null;
    } catch (e) {
      _rows = [];
      _unreadCount = 0;
      _loadError = _friendlyLoadError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openNotification(Map<String, dynamic> row) async {
    final id = int.tryParse('${row['id'] ?? ''}') ?? 0;
    if (id > 0 && '${row['is_read'] ?? 0}' != '1') {
      try {
        await _api.markNotificationRead(id);
      } catch (_) {}
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${row['title'] ?? 'Notification'}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${row['body'] ?? ''}'),
              const SizedBox(height: 12),
              Text(
                '${row['created_at'] ?? ''}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE31B23),
              foregroundColor: Colors.white,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    await _load();
  }

  Future<void> _composeAnnouncement() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final locations = widget.appState.accessibleLocations;
    int? locationId;
    String? formError;
    var sending = false;

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Send Announcement'),
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
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: titleCtrl,
                  enabled: !sending,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bodyCtrl,
                  enabled: !sending,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  value: locationId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Audience'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All accessible stores'),
                    ),
                    ...locations.map(
                      (location) => DropdownMenuItem<int?>(
                        value: location.id,
                        child: Text('${location.name} (${location.type})'),
                      ),
                    ),
                  ],
                  onChanged: sending ? null : (value) => setDialogState(() => locationId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) {
                        setDialogState(() => formError = 'Enter both a title and message.');
                        return;
                      }
                      setDialogState(() {
                        sending = true;
                        formError = null;
                      });
                      try {
                        await _api.sendAnnouncement(
                          title: titleCtrl.text.trim(),
                          body: bodyCtrl.text.trim(),
                          locationId: locationId,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() {
                          formError = ApiClient.friendlyError(e);
                          sending = false;
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE31B23),
                foregroundColor: Colors.white,
              ),
              child: Text(sending ? 'Sending...' : 'Send'),
            ),
          ],
        ),
      ),
    );

    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement sent.')),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobilePageScaffold(
      title: 'Announcements',
      subtitle: 'Channel-style announcements plus important system alerts for your stores.',
      floatingActionButton: _canSend
          ? FloatingActionButton(
              onPressed: _composeAnnouncement,
              backgroundColor: const Color(0xFFE31B23),
              foregroundColor: Colors.white,
              child: const Icon(Icons.campaign_rounded),
            )
          : null,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_loading && _loadError != null && _rows.isEmpty)
              MobileRetryState(
                icon: Icons.wifi_off_rounded,
                title: 'Announcements Are Offline',
                message: _loadError!,
                onRetry: _load,
              )
            else ...[
            if (_loadError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _loadError!,
                  style: const TextStyle(
                    color: Color(0xFFB71C1C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MobileMetricChip('Messages: ${_rows.length}'),
                MobileMetricChip('Unread: $_unreadCount'),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_rows.isEmpty)
              const MobileEmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'No announcements yet',
                message: 'Announcements, variance alerts, and admin updates will appear here.',
              )
            else
              ..._rows.map(
                (row) => MobileActionTile(
                  icon: (row['type'] ?? '').toString().toUpperCase() == 'ANNOUNCEMENT'
                      ? Icons.campaign_rounded
                      : ('${row['is_read'] ?? 0}' == '1'
                          ? Icons.notifications_none_rounded
                          : Icons.notifications_active_rounded),
                  title: '${row['title'] ?? 'Notification'}',
                  subtitle: '${row['body'] ?? ''}\n${row['created_at'] ?? ''}',
                  onTap: () => _openNotification(row),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
