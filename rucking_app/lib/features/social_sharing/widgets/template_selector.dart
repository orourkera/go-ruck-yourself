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
            height: 95, // Further reduce height to prevent overflow
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
          width: 110, // Further reduce width
          padding: const EdgeInsets.all(8), // Reduce padding more
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
                style: const TextStyle(fontSize: 20), // Reduce emoji size more
              ),
              const SizedBox(height: 4), // Reduce spacing more
              Text(
                template.name,
                style: theme.textTheme.bodySmall?.copyWith( // Use even smaller text style
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2), // Keep minimal spacing
              Flexible( // Allow text to shrink if needed
                child: Text(
                  template.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9, // Make description text even smaller
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}