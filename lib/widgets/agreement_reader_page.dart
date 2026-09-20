// agreement_reader_page.dart
// Full-screen reader for the NDA and the Data Privacy Agreement.
//
// These used to live in a box on the last registration step, sharing one phone
// screen with the review summary and the agree checkbox. That left the
// agreements roughly two lines tall -- text nobody can read, let alone
// meaningfully consent to, which makes the consent step a formality rather than
// a real one. Giving them the whole screen is the fix.
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../core/config/agreements.dart';
import '../theme/app_colors.dart';

/// Shows the agreements full screen and resolves to whether the reader reached
/// the end.
///
/// `true` means the bottom was reached, which is what unlocks the agree
/// checkbox back on the review step. Dismissing early resolves to whatever the
/// reader had already achieved, so someone who read it once and comes back to
/// re-check a clause does not lose their progress.
Future<bool> showAgreementReader(
  BuildContext context, {
  bool alreadyRead = false,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => AgreementReaderPage(alreadyRead: alreadyRead),
    ),
  );
  return result ?? alreadyRead;
}

class AgreementReaderPage extends StatefulWidget {
  const AgreementReaderPage({super.key, this.alreadyRead = false});

  /// Starts the page already satisfied, for someone reopening the document.
  final bool alreadyRead;

  @override
  State<AgreementReaderPage> createState() => _AgreementReaderPageState();
}

class _AgreementReaderPageState extends State<AgreementReaderPage> {
  final ScrollController _scrollController = ScrollController();

  /// How far through the document the reader is, 0..1. Drives the thin bar
  /// under the title so the length of what is left is visible rather than a
  /// surprise.
  double _progress = 0;

  /// Sticky once set. Scrolling back up to re-read a clause must not revoke
  /// the fact that the document was read to the end.
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _reachedEnd = widget.alreadyRead;
    _progress = widget.alreadyRead ? 1 : 0;
    _scrollController.addListener(_handleScroll);

    // A document short enough not to scroll -- a tablet, a large-text setting,
    // or a shortened Agreements constant -- emits no scroll event at all. Without
    // this the end could never be reached and registration would be impossible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!mounted || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final max = position.maxScrollExtent;

    // 20px of slack: momentum scrolling and rounding rarely land exactly on
    // maxScrollExtent, and being one pixel short should not block consent.
    final atEnd = max <= 0 || position.pixels >= max - 20;
    final fraction = max <= 0 ? 1.0 : (position.pixels / max).clamp(0.0, 1.0);

    if (fraction != _progress || (atEnd && !_reachedEnd)) {
      setState(() {
        _progress = fraction;
        if (atEnd) _reachedEnd = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          color: AppColors.textPrimary,
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(_reachedEnd),
        ),
        title: const Text(
          'NDA & Data Privacy',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 2,
            backgroundColor: AppColors.borderHairline,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ),
      body: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              MarkdownBody(data: Agreements.ndaText),
              Divider(height: 40, thickness: 1, color: AppColors.borderSubtle),
              MarkdownBody(data: Agreements.dpaText),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.borderHairline)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_reachedEnd)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Scroll to the end to continue',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _reachedEnd
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textInverted,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'I have read the NDA and DPA',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
