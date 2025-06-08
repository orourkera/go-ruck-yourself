import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A reusable user avatar widget that displays profile pictures with fallback to initials
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String username;
  final double size;
  final bool showBorder;
  final Color? borderColor;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    required this.username,
    this.size = 50,
    this.showBorder = false,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget avatarWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(
                color: borderColor ?? Theme.of(context).dividerColor,
                width: 2,
              )
            : null,
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildInitialsAvatar(),
                errorWidget: (context, url, error) => _buildInitialsAvatar(),
                cacheKey: avatarUrl, // Force refresh when URL changes
              )
            : _buildInitialsAvatar(),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatarWidget,
      );
    }

    return avatarWidget;
  }

  Widget _buildInitialsAvatar() {
    final initials = _getInitials(username);
    final backgroundColor = _getColorFromUsername(username);
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    List<String> nameParts = name.split(' ');
    String initials = '';
    if (nameParts.length > 1 && nameParts[0].isNotEmpty && nameParts[1].isNotEmpty) {
      initials = nameParts[0][0] + nameParts[1][0];
    } else if (nameParts.isNotEmpty && nameParts[0].isNotEmpty) {
      initials = nameParts[0][0];
    }
    return initials.toUpperCase();
  }

  Color _getColorFromUsername(String username) {
    // Generate a consistent color from username
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.amber,
      Colors.cyan,
      Colors.lime,
    ];
    
    final hash = username.hashCode;
    return colors[hash.abs() % colors.length];
  }
}

/// Large avatar with edit functionality for profile screens
class EditableUserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String username;
  final double size;
  final VoidCallback onEditPressed;
  final bool isLoading;

  const EditableUserAvatar({
    super.key,
    this.avatarUrl,
    required this.username,
    this.size = 120,
    required this.onEditPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        UserAvatar(
          avatarUrl: avatarUrl,
          username: username,
          size: size,
          showBorder: true,
          borderColor: Theme.of(context).primaryColor,
        ),
        if (isLoading)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: isLoading ? null : onEditPressed,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: size * 0.15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
