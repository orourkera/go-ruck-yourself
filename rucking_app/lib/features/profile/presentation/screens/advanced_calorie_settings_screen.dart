import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/custom_button.dart';
import 'package:rucking_app/shared/widgets/custom_text_field.dart';

class AdvancedCalorieSettingsScreen extends StatefulWidget {
  const AdvancedCalorieSettingsScreen({super.key});

  @override
  State<AdvancedCalorieSettingsScreen> createState() =>
      _AdvancedCalorieSettingsScreenState();
}

class _AdvancedCalorieSettingsScreenState
    extends State<AdvancedCalorieSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _birthdateController; // YYYY-MM-DD
  late TextEditingController _restingHrController;
  late TextEditingController _maxHrController;
  String _method = 'fusion';
  bool _activeOnly = false;

  @override
  void initState() {
    super.initState();
    final authState = GetIt.instance<AuthBloc>().state;
    User? user;
    if (authState is Authenticated) {
      user = authState.user;
    }
    _birthdateController = TextEditingController(text: user?.dateOfBirth ?? '');
    _restingHrController =
        TextEditingController(text: user?.restingHr?.toString() ?? '');
    _maxHrController =
        TextEditingController(text: user?.maxHr?.toString() ?? '');
    _method = user?.calorieMethod ?? 'fusion';
    // Convert deprecated 'hr' method to 'fusion' (HR-based not appropriate for rucking)
    if (_method == 'hr') {
      _method = 'fusion';
    }
    _activeOnly = user?.calorieActiveOnly ?? false;
  }

  @override
  void dispose() {
    _birthdateController.dispose();
    _restingHrController.dispose();
    _maxHrController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _birthdateController.text.isNotEmpty
        ? DateTime.tryParse(_birthdateController.text) ??
            DateTime(now.year - 30)
        : DateTime(now.year - 30);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      _birthdateController.text = picked.toIso8601String().split('T').first;
      setState(() {});
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final resting = _restingHrController.text.isEmpty
        ? null
        : int.tryParse(_restingHrController.text);
    final max = _maxHrController.text.isEmpty
        ? null
        : int.tryParse(_maxHrController.text);

    context.read<AuthBloc>().add(AuthUpdateProfileRequested(
          dateOfBirth: _birthdateController.text.isEmpty
              ? null
              : _birthdateController.text,
          restingHr: resting,
          maxHr: max,
          calorieMethod: _method,
          calorieActiveOnly: _activeOnly,
        ));

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Calorie Tracking'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Personalization',
                  style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFF728C69)
                          : AppColors.textDark)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: CustomTextField(
                    controller: _birthdateController,
                    label: 'Birthdate (for age)',
                    hint: 'YYYY-MM-DD',
                    prefixIcon: Icons.cake_outlined,
                    validator: (v) {
                      if (v == null || v.isEmpty) return null; // optional
                      final ok = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v);
                      if (!ok) return 'Use YYYY-MM-DD';
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      controller: _restingHrController,
                      label: 'Resting HR (bpm)',
                      hint: 'e.g. 60',
                      prefixIcon: Icons.favorite_border,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final n = int.tryParse(v);
                        if (n == null || n < 30 || n > 120) return '30-120';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomTextField(
                      controller: _maxHrController,
                      label: 'Max HR (bpm)',
                      hint: 'e.g. 190',
                      prefixIcon: Icons.flash_on_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final n = int.tryParse(v);
                        if (n == null || n < 100 || n > 240) return '100-240';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Calorie Method',
                  style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFF728C69)
                          : AppColors.textDark)),
              const SizedBox(height: 12),
              _methodTile('Fusion (Recommended)', 'fusion',
                  'Blends HR and mechanical with weather, terrain, and grade awareness. Adjusts for temperature, wind, humidity, and precipitation for maximum accuracy.'),
              _methodTile('Mechanical (Load & Grade)', 'mechanical',
                  'Pure enhanced Pandolf equation exactly as used by GORUCK. Research-based load-ratio corrections for heavy loads, accounting for speed and grade only.'),
              const SizedBox(height: 24),
              Row(
                children: [
                  Switch(
                    value: _activeOnly,
                    onChanged: (v) => setState(() => _activeOnly = v),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Active calories only (subtract resting energy)',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: isDark
                              ? const Color(0xFF728C69)
                              : AppColors.textDark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              CustomButton(
                text: 'Save',
                icon: Icons.save_outlined,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodTile(String title, String value, String subtitle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _method == value;
    return InkWell(
      onTap: () => setState(() => _method = value),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? (isDark ? const Color(0xFF728C69) : AppColors.primary)
                  : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? (isDark ? const Color(0xFF728C69) : AppColors.primary)
                    : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTextStyles.bodyLarge.copyWith(
                          color: isDark
                              ? const Color(0xFF728C69)
                              : AppColors.textDark)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                          color: isDark
                              ? const Color(0xFF728C69).withOpacity(0.8)
                              : AppColors.textDarkSecondary)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
