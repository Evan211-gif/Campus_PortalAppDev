import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

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

      builder: (context, roleSnapshot) {
        if (roleSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Unable to load user role.')),
          );
        }

        if (roleSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = roleSnapshot.data?.data()?['role'];
        final isAdmin = role == 'admin';

        return buildEventsPage(context, isAdmin);
      },
    );
  }

  Widget buildEventsPage(BuildContext context, bool isAdmin) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Events'),
        centerTitle: true,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Archived Events',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ArchivedEventsPage(),
                  ),
                );
              },
            ),
        ],
      ),

      floatingActionButton: isAdmin
          ? FloatingActionButton(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const EventFormDialog(),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,

      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .orderBy('date')
            .snapshots(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Something went wrong loading events.'),
            );
          }

          final events = snapshot.data?.docs ?? [];

          final now = DateTime.now();
          final batch = FirebaseFirestore.instance.batch();
          bool hasExpiredEvents = false;

          for (final event in events) {
            final data = event.data();

            // Skip events that are already archived.
            if (data['status'] == 'archived') {
              continue;
            }

            final dateValue = data['date'];
            final endTime = data['endTimeMinutes'];

            if (dateValue is! Timestamp || endTime is! int) {
              continue;
            }

            final eventDate = dateValue.toDate();

            final eventEnd = DateTime(
              eventDate.year,
              eventDate.month,
              eventDate.day,
            ).add(Duration(minutes: endTime));

            // Archive events whose scheduled end time has passed.
            if (now.isAfter(eventEnd)) {
              batch.update(event.reference, {
                'status': 'archived',
                'archivedAt': FieldValue.serverTimestamp(),
              });

              // Also mark the linked room assignment as archived.
              final assignmentRef = FirebaseFirestore.instance
                  .collection('room_assignments')
                  .doc(event.id);

              batch.set(assignmentRef, {
                'status': 'archived',
              }, SetOptions(merge: true));

              hasExpiredEvents = true;
            }
          }

          // Commit archival updates after the current frame.
          if (hasExpiredEvents) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              batch.commit().catchError((error) {
                debugPrint('Failed to archive expired events: $error');
              });
            });
          }

          // Only show events that are not archived.
          final activeEvents = events.where((event) {
            return event.data()['status'] != 'archived';
          }).toList();

          if (activeEvents.isEmpty) {
            return const Center(child: Text('No upcoming events yet.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Upcoming Events',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 16),

              ...activeEvents.map((event) {
                final data = event.data();

                final title = data['title'] ?? 'Untitled Event';
                final description =
                    data['description'] ?? 'No description available.';
                final location = data['location'] ?? 'Location not specified';

                final dateValue = data['date'];

                String dateText = 'Date not available';

                if (dateValue is Timestamp) {
                  dateText = formatDate(dateValue.toDate());
                }

                return eventCard(
                  context,
                  event.id,
                  title.toString(),
                  dateText,
                  description.toString(),
                  location.toString(),
                  data,
                  isAdmin,
                );
              }),
            ],
          );
        },
      ),
    );
  }

  String formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget eventCard(
    BuildContext context,
    String eventId,
    String title,
    String date,
    String description,
    String location,
    Map<String, dynamic> data,
    bool isAdmin,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 3,
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: const Icon(Icons.event, size: 35, color: Colors.blue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(date),

        trailing: isAdmin
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          EventFormDialog(eventId: eventId, eventData: data),
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue),
                        SizedBox(width: 10),
                        Text('Edit Event'),
                      ],
                    ),
                  ),
                ],
              )
            : null,

        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(
                'Date: $date\n\n'
                'Location: $location\n\n'
                'Description: $description',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> deleteEvent(
    BuildContext context,
    String eventId,
    String title,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Event?'),
        content: Text(
          'Are you sure you want to delete "$title"? '
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
      final firestore = FirebaseFirestore.instance;

      final batch = firestore.batch();

      // Delete the event.
      batch.delete(firestore.collection('events').doc(eventId));

      // Delete its linked room assignment.
      batch.delete(firestore.collection('room_assignments').doc(eventId));

      // Commit both deletions together.
      await batch.commit();

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event and room assignment deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete event: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ADD AND EDIT EVENT FORM

class EventFormDialog extends StatefulWidget {
  final String? eventId;
  final Map<String, dynamic>? eventData;

  const EventFormDialog({super.key, this.eventId, this.eventData});

  @override
  State<EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<EventFormDialog> {
  final _formKey = GlobalKey<FormState>();

  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  DateTime selectedDate = DateTime.now();

  TimeOfDay selectedStartTime = const TimeOfDay(hour: 9, minute: 0);

  TimeOfDay selectedEndTime = const TimeOfDay(hour: 12, minute: 0);

  final List<String> campusLocations = [
    'Classroom 101',
    'Classroom 102',
    'Classroom 103',
    'Classroom 104',
    'Classroom 105',
    'Computer Lab 201',
    'Computer Lab 202',
    'Computer Lab 203',
    'Computer Lab 204',
    'Library',
    'University Gymnasium',
  ];

  String? selectedLocation;

  bool isSaving = false;

  bool get isEditing => widget.eventId != null;

  @override
  void initState() {
    super.initState();

    if (isEditing) {
      final data = widget.eventData!;

      titleController.text = data['title'] ?? '';
      descriptionController.text = data['description'] ?? '';
      final savedLocation = data['location']?.toString();

      selectedLocation = campusLocations.contains(savedLocation)
          ? savedLocation
          : null;

      final dateValue = data['date'];

      if (dateValue is Timestamp) {
        selectedDate = dateValue.toDate();
      }
      // Load saved start time
      final startTimeValue = data['startTimeMinutes'];

      if (startTimeValue is int) {
        selectedStartTime = TimeOfDay(
          hour: startTimeValue ~/ 60,
          minute: startTimeValue % 60,
        );
      }

      // Load saved end time
      final endTimeValue = data['endTimeMinutes'];

      if (endTimeValue is int) {
        selectedEndTime = TimeOfDay(
          hour: endTimeValue ~/ 60,
          minute: endTimeValue % 60,
        );
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (pickedDate != null) {
      setState(() {
        selectedDate = pickedDate;
      });
    }
  }

  Future<void> selectStartTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: selectedStartTime,
    );

    if (pickedTime != null) {
      setState(() {
        selectedStartTime = pickedTime;
      });
    }
  }

  Future<void> selectEndTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: selectedEndTime,
    );

    if (pickedTime != null) {
      setState(() {
        selectedEndTime = pickedTime;
      });
    }
  }

  String formatSelectedDate() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[selectedDate.month - 1]} '
        '${selectedDate.day}, ${selectedDate.year}';
  }

  Future<void> saveEvent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final startMinutes = selectedStartTime.hour * 60 + selectedStartTime.minute;

    final endMinutes = selectedEndTime.hour * 60 + selectedEndTime.minute;

    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be later than start time.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    final firestore = FirebaseFirestore.instance;

    final eventDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

    final dateTimestamp = Timestamp.fromDate(eventDate);

    final eventData = {
      'title': titleController.text.trim(),
      'date': dateTimestamp,
      'description': descriptionController.text.trim(),
      'location': selectedLocation,
      'startTimeMinutes': startMinutes,
      'endTimeMinutes': endMinutes,
    };

    try {
      // STEP 1: Check for duplicate event titles.
      final existingEvents = await firestore.collection('events').get();

      final newTitle = titleController.text.trim().toLowerCase();

      final duplicateExists = existingEvents.docs.any((doc) {
        // Ignore the current event when editing.
        if (isEditing && doc.id == widget.eventId) {
          return false;
        }

        final existingTitle = doc.data()['title'];

        return existingTitle is String &&
            existingTitle.trim().toLowerCase() == newTitle;
      });

      if (duplicateExists) {
        if (!mounted) return;

        setState(() {
          isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An event with this title already exists.'),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      // STEP 2: Check existing room bookings for this date.
      final existingAssignments = await firestore
          .collection('room_assignments')
          .where('date', isEqualTo: dateTimestamp)
          .get();

      for (final assignment in existingAssignments.docs) {
        final data = assignment.data();

        // Ignore the current event when editing.
        if (isEditing && assignment.id == widget.eventId) continue;

        // Only check bookings for the selected location.
        if (data['roomName'] != selectedLocation) continue;

        final existingStart = data['startTimeMinutes'];
        final existingEnd = data['endTimeMinutes'];

        if (existingStart is! int || existingEnd is! int) continue;

        final hasConflict =
            existingStart < endMinutes && existingEnd > startMinutes;

        if (hasConflict) {
          if (!mounted) return;

          setState(() {
            isSaving = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$selectedLocation is already booked during that time.',
              ),
              backgroundColor: Colors.red,
            ),
          );

          return;
        }
      }

      // Check active regular class schedules for the selected weekday and room.
      final classesSnapshot = await firestore
          .collection('classes')
          .where('status', isEqualTo: 'active')
          .get();

      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];

      final selectedDay = weekdays[eventDate.weekday - 1];

      for (final classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final schedules = classData['schedules'];

        if (schedules is! List) continue;

        for (final schedule in schedules) {
          if (schedule is! Map) continue;

          if (schedule['dayOfWeek']?.toString() != selectedDay) continue;
          if (schedule['roomName']?.toString() != selectedLocation) {
            continue;
          }

          final oldStart = schedule['startTimeMinutes'];
          final oldEnd = schedule['endTimeMinutes'];

          if (oldStart is! num || oldEnd is! num) continue;

          final overlaps =
              oldStart.toInt() < endMinutes && oldEnd.toInt() > startMinutes;

          if (overlaps) {
            if (!mounted) return;
            setState(() => isSaving = false);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$selectedLocation is already assigned to '
                  '${classData['subjectName'] ?? 'a class'} on $selectedDay.',
                ),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }
      }

      // Check approved Club Activities on the selected date.
      final activitiesSnapshot = await firestore
          .collection('club_activities')
          .where('status', isEqualTo: 'approved')
          .where('date', isEqualTo: dateTimestamp)
          .get();

      for (final activity in activitiesSnapshot.docs) {
        final data = activity.data();

        if (data['roomName']?.toString() != selectedLocation) continue;

        final oldStart = data['startTimeMinutes'];
        final oldEnd = data['endTimeMinutes'];

        if (oldStart is! num || oldEnd is! num) continue;

        final overlaps =
            oldStart.toInt() < endMinutes && oldEnd.toInt() > startMinutes;

        if (overlaps) {
          if (!mounted) return;
          setState(() => isSaving = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$selectedLocation is already booked for '
                '${data['activityTitle'] ?? 'a Club Activity'}.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // STEP 2: Prepare the event and room assignment references.
      final eventRef = isEditing
          ? firestore.collection('events').doc(widget.eventId)
          : firestore.collection('events').doc();

      final assignmentRef = firestore
          .collection('room_assignments')
          .doc(eventRef.id);

      // STEP 3: Save both documents together.
      final batch = firestore.batch();

      if (isEditing) {
        batch.update(eventRef, eventData);
      } else {
        batch.set(eventRef, {
          ...eventData,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      batch.set(assignmentRef, {
        'eventId': eventRef.id,
        'eventTitle': titleController.text.trim(),
        'roomName': selectedLocation,
        'date': dateTimestamp,
        'startTimeMinutes': startMinutes,
        'endTimeMinutes': endMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Event and room assignment updated successfully!'
                : 'Event and room assignment created successfully!',
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
          content: Text('Failed to save event: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? 'Edit Event' : 'Add New Event'),

      content: SingleChildScrollView(
        child: Form(
          key: _formKey,

          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                enabled: !isSaving,
                decoration: const InputDecoration(
                  labelText: 'Event Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.event),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an event title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedLocation,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                hint: const Text('Select campus location'),
                items: campusLocations.map((location) {
                  return DropdownMenuItem<String>(
                    value: location,
                    child: Text(location),
                  );
                }).toList(),
                onChanged: isSaving
                    ? null
                    : (value) {
                        setState(() {
                          selectedLocation = value;
                        });
                      },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a location';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 14),

              InkWell(
                onTap: isSaving ? null : selectDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Event Date',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_month),
                  ),
                  child: Text(formatSelectedDate()),
                ),
              ),

              const SizedBox(height: 14),

              // START TIME
              InkWell(
                onTap: isSaving ? null : selectStartTime,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Start Time',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time),
                  ),
                  child: Text(selectedStartTime.format(context)),
                ),
              ),

              const SizedBox(height: 14),

              // END TIME
              InkWell(
                onTap: isSaving ? null : selectEndTime,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'End Time',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time_filled),
                  ),
                  child: Text(selectedEndTime.format(context)),
                ),
              ),

              const SizedBox(height: 14),

              TextFormField(
                controller: descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 14),
            ],
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),

        ElevatedButton(
          onPressed: isSaving ? null : saveEvent,
          child: isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Update Event' : 'Save Event'),
        ),
      ],
    );
  }
}

class ArchivedEventsPage extends StatelessWidget {
  const ArchivedEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived Events'), centerTitle: true),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .where('status', isEqualTo: 'archived')
            .orderBy('date')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Something went wrong loading archived events.'),
            );
          }

          final archivedEvents = snapshot.data?.docs ?? [];

          if (archivedEvents.isEmpty) {
            return const Center(child: Text('No archived events yet.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Archived Events',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              ...archivedEvents.map((event) {
                final data = event.data();

                final title = data['title'] ?? 'Untitled Event';
                final description =
                    data['description'] ?? 'No description available.';
                final location = data['location'] ?? 'Location not specified';

                final dateValue = data['date'];

                final dateText = dateValue is Timestamp
                    ? EventsPage().formatDate(dateValue.toDate())
                    : 'Date not available';

                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: ListTile(
                    leading: const Icon(
                      Icons.archive,
                      color: Colors.grey,
                      size: 35,
                    ),
                    title: Text(
                      title.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('$dateText\n$location'),
                    isThreeLine: true,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(title.toString()),
                          content: Text(
                            'Date: $dateText\n\n'
                            'Location: $location\n\n'
                            'Description: $description',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
