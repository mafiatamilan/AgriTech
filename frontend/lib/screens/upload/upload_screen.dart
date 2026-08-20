import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
        title: Text(l10n.uploadPhotoAnalysis),
      ),
      body: const _PhotoAnalysis(),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode A: photo analysis
// ---------------------------------------------------------------------------

class _PhotoAnalysis extends ConsumerStatefulWidget {
  const _PhotoAnalysis();

  @override
  ConsumerState<_PhotoAnalysis> createState() => _PhotoAnalysisState();
}

class _PhotoAnalysisState extends ConsumerState<_PhotoAnalysis> {
  File? _image;
  CropImageUpload? _upload;
  AnalysisStatus? _status;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _image = File(picked.path);
        _upload = null;
        _status = null;
      });
    }
  }

  Future<void> _analyze() async {
    final l10n = AppLocalizations.of(context);
    final farmId = ref.read(farmsProvider).currentFarm?.id;
    if (_image == null) {
      if (mounted) showError(context, l10n.uploadNoImage);
      return;
    }
    if (farmId == null) {
      if (mounted) showError(context, l10n.homeNoFarm);
      return;
    }
    setState(() => _upload = null);
    try {
      final upload = await ref
          .read(backendProvider)
          .uploadCropImage(farmId, _image!);
      setState(() => _upload = upload);
      _poll?.cancel();
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refresh(upload.id),
      );
      _refresh(upload.id);
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _refresh(String id) async {
    try {
      final status = await ref.read(backendProvider).getAnalysisStatus(id);
      if (!mounted) return;
      setState(() => _status = status);
      if (status.isDone || status.isFailed) _poll?.cancel();
    } on Exception {
      // transient — keep polling
    }
  }

  Future<void> _retake() async {
    setState(() {
      _upload = null;
      _status = null;
      _image = null;
    });
    await _pick();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_image!, height: 200, fit: BoxFit.cover),
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.uploadPickImage),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _analyze,
              icon: const Icon(Icons.science_outlined),
              label: Text(l10n.uploadAnalyze),
            ),
          ],
        ),
        if (_upload != null) ...[
          const SizedBox(height: 12),
          Text(l10n.uploadAnalysisStatus(_status?.analysisStatus ?? 'pending')),
          const SizedBox(height: 8),
          if (_status != null && !_status!.isDone && !_status!.isFailed)
            const LinearProgressIndicator(),
          if (_status != null)
            _ResultsView(status: _status!, onRetake: _retake),
        ],
      ],
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.status, required this.onRetake});

  final AnalysisStatus status;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final healthResults = status.results
        .where((r) => r.agentType == 'health')
        .toList();
    final yieldR = status.results.where((r) => r.agentType == 'yield').toList();
    final health = healthResults.isEmpty
        ? null
        : HealthResult.fromJson(healthResults.first.resultJson);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status.isFailed)
          const Card(child: ListTile(title: Text('Analysis failed.'))),
        if (health != null) _HealthCard(health: health, onRetake: onRetake),
        if (yieldR.isNotEmpty)
          _YieldCard(yield: YieldResult.fromJson(yieldR.first.resultJson)),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health, required this.onRetake});

  final HealthResult health;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.uploadHealthStatus,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(health.healthStatus ?? '—'),
            if (health.crop != null) _row(l10n.uploadCrop, health.crop!),
            if (health.disease != null)
              _row(l10n.uploadDisease, health.disease!),
            if (health.diseasesDetected.isNotEmpty)
              _row(l10n.uploadDiseases, health.diseasesDetected.join(', ')),
            if (health.confidenceLevel != null)
              _row(l10n.uploadConfidenceLevel, health.confidenceLevel!),
            if (health.severity != null)
              _row(l10n.uploadSeverity, health.severity!),
            if (health.recommendation != null)
              _row(l10n.uploadRecommendation, health.recommendation!),
            if (health.remedies.isNotEmpty)
              _row(l10n.uploadRemedies, health.remedies.join(' · ')),
            if (health.prevention.isNotEmpty)
              _row(l10n.uploadPrevention, health.prevention.join(' · ')),
            if (health.retakeImage)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: onRetake,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(l10n.uploadRetake),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _YieldCard extends StatelessWidget {
  const _YieldCard({required this.yield});

  final YieldResult yield;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.uploadYieldEstimate,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (yield.cropType != null) _row(l10n.uploadCrop, yield.cropType!),
            _row(
              l10n.uploadYieldEstimate,
              '${yield.expectedYieldKg?.toStringAsFixed(1) ?? '—'} kg',
            ),
            if (yield.confidenceLevel != null)
              _row(l10n.uploadConfidenceLevel, yield.confidenceLevel!),
            if (yield.riskFactors.isNotEmpty)
              _row(l10n.uploadRiskFactors, yield.riskFactors.join(', ')),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
