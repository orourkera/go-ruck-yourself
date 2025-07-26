import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

/// Form widget for importing routes from URLs
class UrlImportForm extends StatefulWidget {
  final Function(String) onSubmit;
  final bool isLoading;

  const UrlImportForm({
    super.key,
    required this.onSubmit,
    this.isLoading = false,
  });

  @override
  State<UrlImportForm> createState() => _UrlImportFormState();
}

class _UrlImportFormState extends State<UrlImportForm> {
  final TextEditingController _urlController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String? _detectedSource;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
    _checkClipboard();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final url = _urlController.text.trim();
    final detectedSource = _detectUrlSource(url);
    
    if (detectedSource != _detectedSource) {
      setState(() {
        _detectedSource = detectedSource;
      });
    }
  }

  Future<void> _checkClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final clipboardText = clipboardData?.text?.trim();
      
      if (clipboardText != null && _isValidUrl(clipboardText)) {
        _showClipboardSuggestion(clipboardText);
      }
    } catch (e) {
      // Ignore clipboard access errors
    }
  }

  void _showClipboardSuggestion(String url) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Found URL in clipboard: ${_truncateUrl(url)}'),
        action: SnackBarAction(
          label: 'Use',
          onPressed: () {
            _urlController.text = url;
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // URL input field
          TextFormField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Route URL',
              hintText: 'https://www.alltrails.com/trail/...',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: _buildSuffixIcon(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.greyLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.primary, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.error, width: 2),
              ),
            ),
            validator: _validateUrl,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitForm(),
            maxLines: 3,
            minLines: 1,
          ),

          const SizedBox(height: 12),

          // Detected source indicator
          if (_detectedSource != null)
            _buildSourceIndicator(_detectedSource!),

          const SizedBox(height: 16),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.isLoading ? null : _submitForm,
              icon: widget.isLoading 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.download),
              label: Text(widget.isLoading ? 'Importing...' : 'Import from URL'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Quick actions
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildSuffixIcon() {
    if (widget.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_urlController.text.isNotEmpty) {
      return IconButton(
        onPressed: () {
          _urlController.clear();
          setState(() {
            _detectedSource = null;
          });
        },
        icon: const Icon(Icons.clear),
        tooltip: 'Clear URL',
      );
    }

    return IconButton(
      onPressed: _pasteFromClipboard,
      icon: const Icon(Icons.content_paste),
      tooltip: 'Paste from clipboard',
    );
  }

  Widget _buildSourceIndicator(String source) {
    IconData icon;
    Color color;
    String displayName;

    switch (source) {
      case 'AllTrails':
        icon = Icons.hiking;
        color = Colors.green;
        displayName = 'AllTrails';
        break;
      case 'Strava':
        icon = Icons.directions_run;
        color = Colors.orange;
        displayName = 'Strava';
        break;
      case 'Garmin':
        icon = Icons.watch;
        color = Colors.blue;
        displayName = 'Garmin Connect';
        break;
      case 'GPX':
        icon = Icons.route;
        color = AppColors.primary;
        displayName = 'GPX File';
        break;
      default:
        icon = Icons.link;
        color = AppColors.textDarkSecondary;
        displayName = 'Generic URL';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            'Detected: $displayName',
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: AppTextStyles.titleSmall.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickActionChip(
              'Paste from Clipboard',
              Icons.content_paste,
              _pasteFromClipboard,
            ),
            _buildQuickActionChip(
              'Clear',
              Icons.clear,
              () {
                _urlController.clear();
                setState(() {
                  _detectedSource = null;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionChip(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.greyLight,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textDarkSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a URL';
    }

    final url = value.trim();
    if (!_isValidUrl(url)) {
      return 'Please enter a valid URL';
    }

    // Check for supported sources
    if (!_isSupportedUrl(url)) {
      return 'URL source not supported. Try AllTrails, Strava, or direct GPX links.';
    }

    return null;
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  bool _isSupportedUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('alltrails.com') ||
           lowerUrl.contains('strava.com') ||
           lowerUrl.contains('garmin.com') ||
           lowerUrl.endsWith('.gpx');
  }

  String? _detectUrlSource(String url) {
    if (url.isEmpty) return null;
    
    final lowerUrl = url.toLowerCase();
    
    if (lowerUrl.contains('alltrails.com')) {
      return 'AllTrails';
    } else if (lowerUrl.contains('strava.com')) {
      return 'Strava';
    } else if (lowerUrl.contains('garmin.com')) {
      return 'Garmin';
    } else if (lowerUrl.endsWith('.gpx')) {
      return 'GPX';
    }
    
    return null;
  }

  String _truncateUrl(String url, {int maxLength = 50}) {
    if (url.length <= maxLength) return url;
    return '${url.substring(0, maxLength - 3)}...';
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        _urlController.text = clipboardData!.text!.trim();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to paste from clipboard');
    }
  }

  void _submitForm() {
    if (_formKey.currentState?.validate() == true) {
      final url = _urlController.text.trim();
      widget.onSubmit(url);
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

/// Compact URL input for smaller spaces
class CompactUrlInput extends StatefulWidget {
  final Function(String) onSubmit;
  final bool isLoading;
  final String? initialUrl;

  const CompactUrlInput({
    super.key,
    required this.onSubmit,
    this.isLoading = false,
    this.initialUrl,
  });

  @override
  State<CompactUrlInput> createState() => _CompactUrlInputState();
}

class _CompactUrlInputState extends State<CompactUrlInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.greyLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Enter URL...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: widget.onSubmit,
            ),
          ),
          IconButton(
            onPressed: widget.isLoading 
                ? null 
                : () => widget.onSubmit(_controller.text.trim()),
            icon: widget.isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            tooltip: 'Import',
          ),
        ],
      ),
    );
  }
}
