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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navUpload)),
      body: Column(
        children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                  value: 0,
                  label: Text(l10n.uploadPhotoAnalysis),
                  icon: const Icon(Icons.photo_camera_outlined)),
              ButtonSegment(
                  value: 1,
                  label: Text(l10n.uploadChatAgent),
                  icon: const Icon(Icons.chat_bubble_outline)),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          Expanded(child: _tab == 0 ? const _PhotoAnalysis() : const _ChatTab()),
        ],
      ),
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
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
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
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh(upload.id));
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
          if (_status != null) _ResultsView(status: _status!),
        ],
      ],
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.status});

  final AnalysisStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final health =
        status.results.where((r) => r.agentType == 'health').toList();
    final yieldR =
        status.results.where((r) => r.agentType == 'yield').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status.isFailed)
          const Card(child: ListTile(title: Text('Analysis failed.'))),
        if (health.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.uploadHealthStatus,
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(health.first.resultJson?['health_status']?.toString() ?? '—'),
                  if (health.first.resultJson?['diseases_detected'] is List &&
                      (health.first.resultJson?['diseases_detected'] as List).isNotEmpty)
                    ...[
                      const SizedBox(height: 8),
                      Text(l10n.uploadDiseases),
                      for (final d
                          in health.first.resultJson['diseases_detected'] as List)
                        Text('• $d'),
                    ],
                ],
              ),
            ),
          ),
        if (yieldR.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.eco_outlined),
              title: Text(l10n.uploadYieldEstimate),
              subtitle: Text(
                '${yieldR.first.resultJson?['expected_yield_kg'] ?? '—'} kg · '
                '${yieldR.first.resultJson?['crop_type'] ?? ''}',
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mode B: chat agent
// ---------------------------------------------------------------------------

class _ChatTab extends ConsumerStatefulWidget {
  const _ChatTab();

  @override
  ConsumerState<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<_ChatTab> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  String? _sessionId;
  File? _pendingImage;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _pendingImage = File(picked.path));
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final image = _pendingImage;
    if (text.isEmpty && image == null) return;
    setState(() {
      _messages.add(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'user',
          content: text,
          imageUrl: image?.path));
      _pendingImage = null;
      _controller.clear();
      _sending = true;
    });
    _scrollDown();
    try {
      _sessionId ??= await ref
          .read(backendProvider)
          .createChatSession(ref.read(farmsProvider).currentFarm?.id);
      final reply = await ref.read(backendProvider).sendChatMessage(
            _sessionId!,
            content: text.isEmpty ? null : text,
            image: image,
          );
      setState(() => _messages.add(reply));
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length + (_sending ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= _messages.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _Bubble(message: _messages[i]);
            },
          ),
        ),
        if (_pendingImage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_pendingImage!,
                      height: 48, width: 48, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _pendingImage = null),
                ),
              ],
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  onPressed: _sending ? null : _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration:
                        InputDecoration(hintText: l10n.uploadAsk, isDense: true),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: Text(l10n.uploadSend),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF2E7D32) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imageUrl != null &&
                (message.imageUrl!.startsWith('http') || message.isUser))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: message.imageUrl!.startsWith('http')
                      ? Image.network(message.imageUrl!, height: 120, fit: BoxFit.cover)
                      : Image.file(File(message.imageUrl!), height: 120, fit: BoxFit.cover),
                ),
              ),
            if (message.content.isNotEmpty)
              Text(
                message.content,
                style: TextStyle(
                    color: isUser ? Colors.white : Colors.black87),
              ),
          ],
        ),
      ),
    );
  }
}