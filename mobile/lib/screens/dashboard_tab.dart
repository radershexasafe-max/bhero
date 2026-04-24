import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import 'bale_movement_screen.dart';
import 'ops_screens.dart';
import 'reports_screen.dart';
import '../models.dart';
import '../widgets/mobile_ui.dart';
import '../widgets/simple_line_chart.dart';

class DashboardTab extends StatefulWidget {
  final AppState appState;
  const DashboardTab({super.key, required this.appState});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  Future<_DashData>? _future;

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0.0;
  }

  bool get _canViewReports {
    return widget.appState.hasPermission('reports.view');
  }

  void _openScreen(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _quickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: widget.appState.hasPermission('day.manage')
                  ? () => _openScreen(CloseShiftScreen(appState: widget.appState))
                  : null,
              icon: const Icon(Icons.play_circle_rounded),
              label: const Text('Start / Close Shift'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE31B23),
                foregroundColor: Colors.white,
              ),
            ),
            if (widget.appState.hasPermission('bale.orders.track'))
              OutlinedButton.icon(
                onPressed: () => _openScreen(BaleMovementScreen(appState: widget.appState)),
                icon: const Icon(Icons.route_rounded),
                label: const Text('Bale Movement'),
              ),
            if (_canViewReports)
              OutlinedButton.icon(
                onPressed: () => _openScreen(ReportsScreen(appState: widget.appState)),
                icon: const Icon(Icons.bar_chart_rounded),
                label: const Text('Bale Reports'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashData> _load() async {
    if (!_canViewReports) {
      return const _DashData();
    }

    final api = ApiClient(baseUrl: widget.appState.baseUrl, token: widget.appState.token);
    final now = DateTime.now();
    final today = _fmt(now);
    final from = _fmt(now.subtract(const Duration(days: 6)));

    final summary = await api.getReportSummary(from: today, to: today, locationId: null);
    final seriesRows = await api.getReportTimeSeries(from: from, to: today);
    final sales = seriesRows.map((row) => _toDouble(row['sales'])).toList();

    return _DashData(summary: summary, salesSeries: sales, seriesFrom: from, seriesTo: today);
  }

  static String _fmt(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    if (!_canViewReports) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const MobileHeroCard(
            title: 'Dashboard',
            subtitle: 'Quick sales access is available. Reports and transfers are restricted for your role.',
          ),
          const SizedBox(height: 16),
          _quickActions(),
        ],
      );
    }

    return FutureBuilder<_DashData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final friendlyMessage = ApiClient.friendlyError(
            snapshot.error!,
            fallback: ApiClient.connectionFallback,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const MobileHeroCard(
                title: 'Dashboard',
                subtitle: 'Check your internet connection and tap Reload to try again.',
              ),
              const SizedBox(height: 16),
              _quickActions(),
              const SizedBox(height: 16),
              MobileRetryState(
                icon: Icons.error_outline_rounded,
                title: 'Dashboard Is Offline Right Now',
                message: friendlyMessage,
                onRetry: () => setState(() => _future = _load()),
              ),
            ],
          );
        }

        final data = snapshot.data ?? const _DashData();
        final s = data.summary;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MobileHeroCard(
              title: 'Dashboard',
              subtitle: 'Today at a glance plus your last 7 days of sales.',
              trailing: [
                IconButton(
                  onPressed: () => setState(() => _future = _load()),
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _quickActions(),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(title: 'Sales Today', value: (s?.totalSales ?? 0).toStringAsFixed(0)),
                _MetricCard(title: 'Gross Profit', value: (s?.grossProfit ?? 0).toStringAsFixed(0)),
                _MetricCard(title: 'Expenses', value: (s?.expenses ?? 0).toStringAsFixed(0)),
                _MetricCard(title: 'Net Profit', value: (s?.netProfit ?? 0).toStringAsFixed(0)),
                _MetricCard(title: 'Start Cash', value: s?.startCash == null ? '-' : s!.startCash!.toStringAsFixed(0)),
                _MetricCard(title: 'Closing Cash', value: s?.closingCash == null ? '-' : s!.closingCash!.toStringAsFixed(0)),
              ],
            ),
            const SizedBox(height: 16),
            MobileSectionCard(
              icon: Icons.show_chart_rounded,
              title: 'Sales Trend',
              subtitle: '${data.seriesFrom} to ${data.seriesTo}',
              child: SimpleLineChart(
                values: data.salesSeries,
                title: 'Sales (last 7 days)',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const _MetricCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashData {
  final ReportSummary? summary;
  final List<double> salesSeries;
  final String seriesFrom;
  final String seriesTo;

  const _DashData({
    this.summary,
    this.salesSeries = const [],
    this.seriesFrom = '',
    this.seriesTo = '',
  });
}
