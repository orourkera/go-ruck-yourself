import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rucking_app/core/services/image_cache_manager.dart';

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
            ? _buildAvatarImage()
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

  Widget _buildAvatarImage() {
    // Check if the avatarUrl is a local file path
    // More robust detection for file paths and file:// URLs
    final isLocalFile = avatarUrl!.startsWith('file://') || 
                       avatarUrl!.startsWith('/') ||
                       avatarUrl!.contains('/var/mobile/') ||
                       avatarUrl!.contains('/data/data/') ||
                       avatarUrl!.contains('cropped_image_');
    
    if (isLocalFile) {
      // Handle local file
      String filePath = avatarUrl!;
      
      // Remove file:// prefix if present
      if (filePath.startsWith('file://')) {
        filePath = filePath.replaceFirst('file://', '');
      }
      
      final file = File(filePath);
      
      // Check if file exists before trying to display it
      return FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildInitialsAvatar();
          }
          
          if (snapshot.data == true) {
            return Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Error loading local avatar file: $error');
                return _buildInitialsAvatar();
              },
            );
          } else {
            debugPrint('Local avatar file does not exist: $filePath');
            return _buildInitialsAvatar();
          }
        },
      );
    }
    
    // Handle network URL - ensure it's a valid HTTP/HTTPS URL
    if (avatarUrl!.startsWith('http://') || avatarUrl!.startsWith('https://')) {
      return Builder(
        builder: (context) {
          try {
            return CachedNetworkImage(
              imageUrl: avatarUrl!,
              cacheManager: ImageCacheManager.profileCache,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (context, url) => _buildInitialsAvatar(),
              errorWidget: (context, url, error) {
                debugPrint('Error loading network avatar: $error');
                // Handle all types of network errors gracefully
                return _buildInitialsAvatar();
              },
              cacheKey: avatarUrl,
              // Enhanced timeout and retry configuration
              httpHeaders: const {
                'Connection': 'keep-alive',
                'Cache-Control': 'max-age=3600',
              },
              // Add error listener to handle network issues gracefully
              errorListener: (error) {
                debugPrint('Avatar loading error: $error');
              },
            );
          } catch (e, stackTrace) {
            // Catch any uncaught exceptions during avatar loading
            debugPrint('Avatar loading crashed: $e');
            debugPrint('Stack trace: $stackTrace');
            return _buildInitialsAvatar();
          }
        },
      );
    }
    
    // If it's not a recognized URL format, show initials
    debugPrint('Unrecognized avatar URL format: $avatarUrl');
    return _buildInitialsAvatar();
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
