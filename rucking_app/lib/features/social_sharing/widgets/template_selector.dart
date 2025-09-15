import 'package:flutter/material.dart';
import 'package:rucking_app/features/social_sharing/models/post_template.dart';

/// Widget for selecting post templates
class TemplateSelector extends StatelessWidget {
  final PostTemplate selectedTemplate;
  final ValueChanged<PostTemplate> onTemplateSelected;

  const TemplateSelector({
    Key? key,
    required this.selectedTemplate,
    required this.onTemplateSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your Style',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110, // Reduce height slightly
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: PostTemplate.values.length,
              itemBuilder: (context, index) {
                final template = PostTemplate.values[index];
                return _buildTemplateCard(context, template);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(BuildContext context, PostTemplate template) {
    final isSelected = selectedTemplate == template;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () => onTemplateSelected(template),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 120, // Reduce width slightly
          padding: const EdgeInsets.all(10), // Reduce padding slightly
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withOpacity(0.3),
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.05)
                : theme.colorScheme.surface,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                template.emoji,
                style: const TextStyle(fontSize: 24), // Reduce emoji size
              ),
              const SizedBox(height: 6), // Reduce spacing
              Text(
                template.name,
                style: theme.textTheme.bodyMedium?.copyWith( // Use smaller text style
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2), // Reduce spacing
              Text(
                template.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}