import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  bool showingArchived = false;

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
            actions: [
              if (isAdmin)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      showingArchived = !showingArchived;
                    });
                  },
                  icon: Icon(
                    showingArchived
                        ? Icons.campaign_outlined
                        : Icons.archive_outlined,
                  ),
                  label: Text(showingArchived ? 'Published' : 'Archived'),
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

              final announcements = snapshot.data?.docs ?? [];

              if (announcements.isEmpty) {
                return const Center(child: Text('No announcements available.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: announcements.length,
                itemBuilder: (context, index) {
                  final data = announcements[index].data();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(
                        Icons.campaign_outlined,
                        color: Colors.blue,
                      ),
                      title: Text(
                        data['title'] ?? 'Untitled Announcement',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        data['description'] ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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
                                            announcementId:
                                                announcements[index].id,
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
                                          'Archive Announcement',
                                        ),
                                        content: const Text(
                                          'Are you sure you want to archive this announcement?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                              dialogContext,
                                              false,
                                            ),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
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
                                          .doc(announcements[index].id)
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

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to archive announcement: $error',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
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
}

class CreateAnnouncementDialog extends StatefulWidget {
  final String? announcementId;
  final Map<String, dynamic>? existingData;

  const CreateAnnouncementDialog({
    super.key,
    this.announcementId,
    this.existingData,
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

  @override
  void initState() {
    super.initState();

    final data = widget.existingData;

    if (data != null) {
      titleController.text = data['title'] ?? '';
      descriptionController.text = data['description'] ?? '';

      selectedCategory = categories.contains(data['category'])
          ? data['category']
          : 'General';

      isPinned = data['pinned'] == true;
    }
  }

  String selectedCategory = 'General';
  bool isPinned = false;
  bool isSaving = false;

  final categories = ['General', 'Academic', 'Events', 'Emergency'];

  Future<void> publishAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() {
      isSaving = true;
    });

    try {
      final announcementData = {
        'title': titleController.text.trim(),
        'description': descriptionController.text.trim(),
        'category': selectedCategory,
        'pinned': isPinned,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.isEditing) {
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
            widget.isEditing
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
          content: Text('Failed to publish announcement: $error'),
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
      title: const Text('Create Announcement'),
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
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedCategory = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
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
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pin this announcement'),
                  value: isPinned,
                  onChanged: (value) {
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
              : const Text('Publish'),
        ),
      ],
    );
  }
}
