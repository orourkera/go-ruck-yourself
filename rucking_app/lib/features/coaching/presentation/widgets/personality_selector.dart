import 'package:flutter/material.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_personality.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class PersonalitySelector extends StatefulWidget {
  final void Function(CoachingPersonality) onPersonalitySelected;

  const PersonalitySelector({
    super.key,
    required this.onPersonalitySelected,
  });

  @override
  State<PersonalitySelector> createState() => _PersonalitySelectorState();
}

class _PersonalitySelectorState extends State<PersonalitySelector> {
  CoachingPersonality? _selectedPersonality;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Personality Pills
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: CoachingPersonality.allPersonalities.map((personality) {
            final isSelected = _selectedPersonality?.id == personality.id;
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPersonality = personality;
                });
                // Don't call widget.onPersonalitySelected immediately - let user see the example first
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected 
                    ? personality.color 
                    : personality.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: personality.color.withOpacity(isSelected ? 1.0 : 0.3),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: personality.color.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      personality.icon,
                      color: isSelected 
                        ? Colors.white 
                        : personality.color,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      personality.name,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isSelected 
                          ? Colors.white 
                          : personality.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        
        const SizedBox(height: 32),
        
        // Dynamic Example Display
        if (_selectedPersonality != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _selectedPersonality!.color.withOpacity(0.15),
                  _selectedPersonality!.color.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _selectedPersonality!.color.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedPersonality!.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _selectedPersonality!.icon,
                        color: _selectedPersonality!.color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedPersonality!.name,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _selectedPersonality!.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedPersonality!.description,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.grey[600],
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Example quote
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _selectedPersonality!.color.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.format_quote,
                        color: _selectedPersonality!.color.withOpacity(0.7),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedPersonality!.example,
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontStyle: FontStyle.italic,
                            color: _selectedPersonality!.color.withOpacity(0.9),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Placeholder when no personality is selected
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.grey.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.touch_app,
                  color: Colors.grey[400],
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Tap a coaching style above to see an example',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
        
        // Continue Button (appears when personality is selected)
        if (_selectedPersonality != null) ...[
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => widget.onPersonalitySelected(_selectedPersonality!),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedPersonality!.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: _selectedPersonality!.color.withOpacity(0.3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue with ${_selectedPersonality!.name}',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}