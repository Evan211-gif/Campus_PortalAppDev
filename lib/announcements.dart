import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ==========================================
// ANNOUNCEMENT TITLE NORMALIZATION
// ==========================================

String normalizeAnnouncementTitle(String title) {
  var normalized = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  if (normalized.endsWith('ies') && normalized.length > 4) {
    normalized = '${normalized.substring(0, normalized.length - 3)}y';
  } else if (RegExp(r'(sses|shes|ches|xes|zes)$').hasMatch(normalized)) {
    normalized = normalized.substring(0, normalized.length - 2);
  } else if (normalized.endsWith('s') &&
      !normalized.endsWith('ss') &&
      normalized.length > 3) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  return normalized;
}

DateTime dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

// ==========================================
// DATE FORMAT: MM/DD/YYYY
// ==========================================

String formatDate(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.year}';
}

// ==========================================
// ANNOUNCEMENTS PAGE
// ==========================================

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  bool showingArchived = false;

  // ==========================================
  // PERMANENTLY DELETE ARCHIVED ANNOUNCEMENT
  // ==========================================

  Future<void> _deleteAnnouncement(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Announcement?'),
        content: const Text(
          'This announcement will be permanently deleted. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await doc.reference.delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Announcement permanently deleted.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete announcement: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in first.')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: Text('User profile not found.')),
          );
        }

        final role = userSnapshot.data!.data()?['role'];

        if (!['admin', 'student', 'teacher'].contains(role)) {
          return const Scaffold(
            body: Center(child: Text('You do not have permission.')),
          );
        }

        final isAdmin = role == 'admin';

        return Scaffold(
          appBar: AppBar(
            title: Text(
              showingArchived ? 'Archived Announcements' : 'Announcements',
            ),
            leading: showingArchived
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        showingArchived = false;
                      });
                    },
                  )
                : null,
            actions: [
              if (isAdmin && !showingArchived)
                IconButton(
                  tooltip: 'View Archived Announcements',
                  icon: const Icon(Icons.archive_outlined, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      showingArchived = true;
                    });
                  },
                ),
            ],
          ),

          floatingActionButton: isAdmin
              ? FloatingActionButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const CreateAnnouncementDialog(),
                    );
                  },
                  child: const Icon(Icons.add),
                )
              : null,

          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('announcements')
                .where(
                  'status',
                  isEqualTo: showingArchived ? 'archived' : 'published',
                )
                .orderBy('publishedAt', descending: true)
                .snapshots(),

            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Something went wrong loading announcements.'),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final today = dateOnly(DateTime.now());

              final announcements = (snapshot.data?.docs ?? []).where((doc) {
                if (showingArchived) return true;

                final data = doc.data();

                final start = (data['publishDate'] as Timestamp?)?.toDate();
                final end = (data['endDate'] as Timestamp?)?.toDate();

                // Keep older announcements without date fields.
                if (start == null || end == null) return true;

                final startDay = dateOnly(start);
                final endDay = dateOnly(end);

                return !today.isBefore(startDay) && !today.isAfter(endDay);
              }).toList();

              // Pinned announcements always appear first.
              announcements.sort((a, b) {
                final aPinned = a.data()['pinned'] == true;
                final bPinned = b.data()['pinned'] == true;

                if (aPinned != bPinned) {
                  return aPinned ? -1 : 1;
                }

                final aDate = a.data()['publishedAt'] as Timestamp?;
                final bDate = b.data()['publishedAt'] as Timestamp?;

                return (bDate?.compareTo(aDate ?? Timestamp(0, 0)) ?? 0);
              });

              if (announcements.isEmpty) {
                return const Center(child: Text('No announcements available.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: announcements.length,
                itemBuilder: (context, index) {
                  final announcement = announcements[index];
                  final data = announcement.data();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(
                        showingArchived
                            ? Icons.archive_outlined
                            : Icons.campaign_outlined,
                        size: 35,
                        color: Colors.blue,
                      ),

                      title: Text(
                        data['title'] ?? 'Untitled Announcement',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),

                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['description'] ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),

                          if (data['publishDate'] != null)
                            Text(
                              'Posted: ${_formatDate(data['publishDate'])}',
                              style: const TextStyle(fontSize: 12),
                            ),

                          if (data['endDate'] != null)
                            Text(
                              'Until: ${_formatDate(data['endDate'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),

                      trailing: isAdmin
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (data['pinned'] == true)
                                  const Icon(
                                    Icons.push_pin,
                                    color: Colors.orange,
                                  ),

                                // PUBLISHED ANNOUNCEMENT ACTIONS
                                if (!showingArchived) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.blue,
                                    ),
                                    tooltip: 'Edit Announcement',
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (dialogContext) =>
                                            CreateAnnouncementDialog(
                                              announcementId: announcement.id,
                                              existingData: data,
                                            ),
                                      );
                                    },
                                  ),

                                  IconButton(
                                    icon: const Icon(
                                      Icons.archive_outlined,
                                      color: Colors.orange,
                                    ),
                                    tooltip: 'Archive Announcement',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text(
                                            'Archive Announcement?',
                                          ),
                                          content: const Text(
                                            'This announcement will be moved '
                                            'to Archived Announcements.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                false,
                                              ),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                true,
                                              ),
                                              child: const Text('Archive'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm != true) return;

                                      try {
                                        await FirebaseFirestore.instance
                                            .collection('announcements')
                                            .doc(announcement.id)
                                            .update({
                                              'status': 'archived',
                                              'archivedAt':
                                                  FieldValue.serverTimestamp(),
                                            });

                                        if (!context.mounted) return;

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Announcement archived successfully.',
                                                ),
                                              ),
                                            );
                                      } catch (error) {
                                        if (!context.mounted) return;

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Failed to archive: $error',
                                                ),
                                              ),
                                            );
                                      }
                                    },
                                  ),
                                ]
                                // ARCHIVED ANNOUNCEMENT ACTIONS
                                else ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.restore,
                                      color: Colors.green,
                                    ),
                                    tooltip: 'Edit and Restore',
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (dialogContext) =>
                                            CreateAnnouncementDialog(
                                              announcementId: announcement.id,
                                              existingData: data,
                                              restoreAfterSave: true,
                                            ),
                                      );
                                    },
                                  ),

                                  // DELETE BUTTON
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    tooltip: 'Delete Permanently',
                                    onPressed: () =>
                                        _deleteAnnouncement(announcement),
                                  ),
                                ],
                              ],
                            )
                          : data['pinned'] == true
                          ? const Icon(Icons.push_pin, color: Colors.orange)
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  String _formatDate(dynamic value) {
    if (value is! Timestamp) return '';

    return formatDate(value.toDate());
  }
}

// ==========================================
// CREATE / EDIT ANNOUNCEMENT DIALOG
// ==========================================

class CreateAnnouncementDialog extends StatefulWidget {
  final String? announcementId;
  final Map<String, dynamic>? existingData;
  final bool restoreAfterSave;

  const CreateAnnouncementDialog({
    super.key,
    this.announcementId,
    this.existingData,
    this.restoreAfterSave = false,
  });

  bool get isEditing => announcementId != null;

  @override
  State<CreateAnnouncementDialog> createState() =>
      _CreateAnnouncementDialogState();
}

class _CreateAnnouncementDialogState extends State<CreateAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();

  final titleController = TextEditingController();
  final descriptionController = TextEditingController();

  String selectedCategory = 'General';
  bool isPinned = false;
  bool isSaving = false;

  DateTime publishDate = dateOnly(DateTime.now());
  DateTime? endDate;

  final categories = ['General', 'Academic', 'Events', 'Emergency'];

  @override
  void initState() {
    super.initState();

    final data = widget.existingData;

    if (data != null) {
      final savedPublishDate = data['publishDate'] as Timestamp?;
      final savedEndDate = data['endDate'] as Timestamp?;

      publishDate = savedPublishDate != null
          ? dateOnly(savedPublishDate.toDate())
          : dateOnly(DateTime.now());

      endDate = savedEndDate != null ? dateOnly(savedEndDate.toDate()) : null;

      titleController.text = data['title'] ?? '';
      descriptionController.text = data['description'] ?? '';

      selectedCategory = categories.contains(data['category'])
          ? data['category']
          : 'General';

      isPinned = data['pinned'] == true;
    }
  }

  Future<void> selectPublishDate() async {
    final today = dateOnly(DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: publishDate.isBefore(today) ? today : publishDate,
      firstDate: today,
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        publishDate = dateOnly(picked);

        if (endDate != null && dateOnly(endDate!).isBefore(publishDate)) {
          endDate = null;
        }
      });
    }
  }

  Future<void> selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endDate == null || dateOnly(endDate!).isBefore(publishDate)
          ? publishDate
          : endDate!,
      firstDate: publishDate,
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        endDate = dateOnly(picked);
      });
    }
  }

  Future<void> publishAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final today = dateOnly(DateTime.now());

    if (endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an end date.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (dateOnly(endDate!).isBefore(dateOnly(publishDate))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date cannot be before publish date.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // New announcements and restored announcements cannot
    // have a publish date earlier than today.
    if ((!widget.isEditing || widget.restoreAfterSave) &&
        dateOnly(publishDate).isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publish date cannot be in the past.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final enteredTitle = titleController.text.trim();

      final normalizedTitle = normalizeAnnouncementTitle(enteredTitle);

      // Check published AND archived announcements.
      final existingAnnouncements = await FirebaseFirestore.instance
          .collection('announcements')
          .get();

      final duplicateExists = existingAnnouncements.docs.any((doc) {
        if (widget.isEditing && doc.id == widget.announcementId) {
          return false;
        }

        final existingTitle = doc.data()['title']?.toString() ?? '';

        return normalizeAnnouncementTitle(existingTitle) == normalizedTitle;
      });

      if (duplicateExists) {
        if (!mounted) return;

        setState(() {
          isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An announcement with this title already exists.'),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      final announcementData = <String, dynamic>{
        'title': enteredTitle,
        'description': descriptionController.text.trim(),
        'category': selectedCategory,
        'pinned': isPinned,
        'publishDate': Timestamp.fromDate(dateOnly(publishDate)),
        'endDate': Timestamp.fromDate(dateOnly(endDate!)),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.isEditing) {
        if (widget.restoreAfterSave) {
          announcementData['status'] = 'published';
          announcementData['archivedAt'] = FieldValue.delete();
        }

        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(widget.announcementId)
            .update(announcementData);
      } else {
        await FirebaseFirestore.instance.collection('announcements').add({
          ...announcementData,
          'status': 'published',
          'publishedAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
        });
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.restoreAfterSave
                ? 'Announcement updated and restored successfully!'
                : widget.isEditing
                ? 'Announcement updated successfully!'
                : 'Announcement published successfully!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save announcement: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.restoreAfterSave
            ? 'Edit and Restore Announcement'
            : widget.isEditing
            ? 'Edit Announcement'
            : 'Create Announcement',
      ),

      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Announcement Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a title.';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // PUBLISH DATE
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publish Date'),
                  subtitle: Text(formatDate(publishDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: isSaving ? null : selectPublishDate,
                ),

                // END DATE
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End Date'),
                  subtitle: Text(
                    endDate == null
                        ? 'Select when this announcement expires'
                        : formatDate(endDate!),
                  ),
                  trailing: const Icon(Icons.event_busy),
                  onTap: isSaving ? null : selectEndDate,
                ),

                if (endDate == null)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Please select an end date.',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),

                const SizedBox(height: 16),

                // CATEGORY
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: categories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              selectedCategory = value;
                            });
                          }
                        },
                ),

                const SizedBox(height: 16),

                // DESCRIPTION
                TextFormField(
                  controller: descriptionController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a description.';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 8),

                // PIN ANNOUNCEMENT
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pin this announcement'),
                  value: isPinned,
                  onChanged: isSaving
                      ? null
                      : (value) {
                          setState(() {
                            isPinned = value ?? false;
                          });
                        },
                ),
              ],
            ),
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),

        ElevatedButton(
          onPressed: isSaving ? null : publishAnnouncement,
          child: isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  widget.restoreAfterSave
                      ? 'Save and Restore'
                      : widget.isEditing
                      ? 'Save Changes'
                      : 'Publish',
                ),
        ),
      ],
    );
  }
}
