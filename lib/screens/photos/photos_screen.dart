import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../models/photo.dart';
import '../../providers/photo_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';

class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (pickedFile == null || !mounted) return;

    final file = File(pickedFile.path);

    _showUploadSheet(file, baby.id);
  }

  void _showUploadSheet(File file, String babyId) {
    final captionController = TextEditingController();
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Add Photo',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: ctx.palette.text,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      file,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: captionController,
                    decoration: InputDecoration(
                      labelText: 'Caption (optional)',
                      hintText: 'Add a caption...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      filled: true,
                      fillColor: ctx.palette.surface,
                    ),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isUploading
                          ? null
                          : () async {
                              setSheetState(() => isUploading = true);
                              try {
                                final photo = await PhotoActions.uploadPhoto(
                                  babyId: babyId,
                                  file: file,
                                  caption: captionController.text.trim().isEmpty
                                      ? null
                                      : captionController.text.trim(),
                                );
                                if (photo != null) {
                                  ref.invalidate(photosProvider);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    context.showSuccessSnackBar(
                                        'Photo uploaded!');
                                  }
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ctx.showErrorSnackBar(
                                    'Couldn’t upload the photo. Check your connection and try again.',
                                  );
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setSheetState(() => isUploading = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: isUploading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Upload',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleDelete(Photo photo) async {
    final confirmed = await showDeleteDialog(context, what: 'Photo');

    if (!confirmed) return;

    try {
      await PhotoActions.deletePhoto(photo);
      ref.invalidate(photosProvider);
      if (mounted) {
        context.showSuccessSnackBar('Photo deleted');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t delete the photo. Check your connection and try again.',
        );
      }
    }
  }

  void _openFullscreenViewer(List<Photo> photos, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenPhotoViewer(
          photos: photos,
          initialIndex: initialIndex,
          onDelete: _handleDelete,
        ),
      ),
    );
  }

  Map<String, List<Photo>> _groupByMonth(List<Photo> photos) {
    final grouped = <String, List<Photo>>{};
    for (final photo in photos) {
      final key = AppDateUtils.formatMonthYear(photo.takenAt ?? photo.createdAt);
      grouped.putIfAbsent(key, () => []).add(photo);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos'),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSourcePicker(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_a_photo_rounded),
      ),
      body: SafeArea(
        child: photosAsync.when(
          data: (photos) {
            if (photos.isEmpty) {
              return const EmptyState(
                icon: Icons.photo_library_rounded,
                title: 'No photos yet',
                description: 'Tap the camera button to add your first photo',
              );
            }

            final grouped = _groupByMonth(photos);
            final months = grouped.keys.toList();

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: months.length,
              itemBuilder: (context, monthIndex) {
                final month = months[monthIndex];
                final monthPhotos = grouped[month]!;

                // Compute flat index offset for fullscreen viewer
                int flatOffset = 0;
                for (int i = 0; i < monthIndex; i++) {
                  flatOffset += grouped[months[i]]!.length;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 4,
                      ),
                      child: Text(
                        month,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.palette.text,
                        ),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: monthPhotos.length,
                      itemBuilder: (context, index) {
                        final photo = monthPhotos[index];
                        return GestureDetector(
                          onTap: () => _openFullscreenViewer(
                            photos,
                            flatOffset + index,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: photo.url,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(
                                color: AppColors.pastelPurple.withValues(alpha: 0.3),
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (_, _, _) => Container(
                                color: Colors.grey.shade200,
                                child: const Icon(
                                  Icons.broken_image_rounded,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
          loading: () => const LoadingSkeleton(),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: context.palette.muted),
                const SizedBox(height: 12),
                Text(
                  'Failed to load photos',
                  style: TextStyle(color: context.palette.muted),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(photosProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add Photo',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: ctx.palette.text,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.pastelPurple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.camera_alt_rounded, color: AppColors.primary),
              ),
              title: const Text('Take Photo'),
              subtitle: Text(
                'Use your camera',
                style: TextStyle(color: ctx.palette.muted, fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadPhoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.pastelPurple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primary,
                ),
              ),
              title: const Text('Choose from Gallery'),
              subtitle: Text(
                'Select an existing photo',
                style: TextStyle(color: ctx.palette.muted, fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FullscreenPhotoViewer extends StatefulWidget {
  final List<Photo> photos;
  final int initialIndex;
  final Future<void> Function(Photo photo) onDelete;

  const _FullscreenPhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<_FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<_FullscreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final photo = widget.photos[_currentIndex];
              await widget.onDelete(photo);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          final photo = widget.photos[index];
          return Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 3.0,
                  child: CachedNetworkImage(
                    imageUrl: photo.url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    errorWidget: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
              if (photo.caption != null && photo.caption!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.black87,
                  child: Text(
                    photo.caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
