import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/conversion_analytics.dart';
import '../utils/premium_access.dart';

class ConversionDiagnosticsScreen extends StatefulWidget {
  const ConversionDiagnosticsScreen({super.key});

  @override
  State<ConversionDiagnosticsScreen> createState() =>
      _ConversionDiagnosticsScreenState();
}

class _ConversionDiagnosticsScreenState extends State<ConversionDiagnosticsScreen> {
  bool _loading = true;
  bool _allowed = false;
  List<ConversionEventRecord> _records = const <ConversionEventRecord>[];
  ConversionFunnelSummary _summary = const ConversionFunnelSummary(
    paywallViews: 0,
    trialStarts: 0,
    subscribes: 0,
    churns: 0,
    immediateChurns: 0,
    viewToTrialRate: 0,
    trialToSubscribeRate: 0,
    viewToSubscribeRate: 0,
    immediateChurnRate: 0,
    overallChurnPerSubscribeRate: 0,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final testingAvailable = await PremiumAccess.isTestingModeAvailable();
    final allowed = kDebugMode || kIsWeb || testingAvailable;

    if (!allowed) {
      if (!mounted) return;
      setState(() {
        _allowed = false;
        _loading = false;
      });
      return;
    }

    final records = await ConversionAnalytics.readEventLog();
    final summary = ConversionAnalytics.summarizeFunnel(records);

    if (!mounted) return;
    setState(() {
      _allowed = true;
      _records = records.reversed.toList(growable: false);
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await ConversionAnalytics.clearEventLog();
    await _load();
  }

  String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.refinedSlate,
        title: const Text(
          'Conversion Diagnostics',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
          ? _blockedView()
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  _summaryCard(),
                  const SizedBox(height: 12),
                  _funnelCard(),
                  const SizedBox(height: 12),
                  _churnCard(),
                  const SizedBox(height: 12),
                  _eventsCard(),
                ],
              ),
            ),
    );
  }

  Widget _blockedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borders),
          ),
          child: const Text(
            'Diagnostics are available only in debug, web, or local testing mode.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.refinedSlate,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return _card(
      title: 'Cohort Snapshot',
      child: Row(
        children: [
          _statTile('Events', _records.length.toString()),
          const SizedBox(width: 10),
          _statTile('Paywall Views', _summary.paywallViews.toString()),
          const SizedBox(width: 10),
          _statTile('Subscribes', _summary.subscribes.toString()),
        ],
      ),
    );
  }

  Widget _funnelCard() {
    return _card(
      title: 'Funnel',
      child: Column(
        children: [
          _metricRow('paywall_view -> trial_start', _pct(_summary.viewToTrialRate)),
          const SizedBox(height: 8),
          _metricRow('trial_start -> subscribe', _pct(_summary.trialToSubscribeRate)),
          const SizedBox(height: 8),
          _metricRow('paywall_view -> subscribe', _pct(_summary.viewToSubscribeRate)),
        ],
      ),
    );
  }

  Widget _churnCard() {
    return _card(
      title: 'Churn',
      child: Column(
        children: [
          _metricRow('Immediate churn count', _summary.immediateChurns.toString()),
          const SizedBox(height: 8),
          _metricRow('Immediate churn / subscribe', _pct(_summary.immediateChurnRate)),
          const SizedBox(height: 8),
          _metricRow('Total churn / subscribe', _pct(_summary.overallChurnPerSubscribeRate)),
        ],
      ),
    );
  }

  Widget _eventsCard() {
    return _card(
      title: 'Recent Events',
      trailing: TextButton.icon(
        onPressed: _records.isEmpty ? null : _clear,
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        label: const Text('Clear'),
      ),
      child: _records.isEmpty
          ? Text(
              'No conversion events logged yet.',
              style: TextStyle(
                color: AppColors.refinedSlate.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < _records.length && i < 40; i++)
                  _eventRow(_records[i], i == 0),
              ],
            ),
    );
  }

  Widget _eventRow(ConversionEventRecord record, bool first) {
    final time = record.timestamp.toLocal().toString().replaceFirst('T', ' ');
    return Container(
      margin: EdgeInsets.only(top: first ? 0 : 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borders.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.event,
                  style: const TextStyle(
                    color: AppColors.refinedSlate,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: TextStyle(
                    color: AppColors.refinedSlate.withValues(alpha: 0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (record.properties.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                record.properties.toString(),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppColors.refinedSlate.withValues(alpha: 0.75),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.refinedSlate,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borders.withValues(alpha: 0.75)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.refinedSlate.withValues(alpha: 0.65),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.refinedSlate,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.refinedSlate,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
