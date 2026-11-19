import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';

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
        leading: const Icon(Icons.event, color: Colors.blue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$date\n$description'),

        trailing: isAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit Event',
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (dialogContext) =>
                            EventFormDialog(eventId: eventId, eventData: data),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Archive Event',
                    icon: const Icon(
                      Icons.archive_outlined,
                      color: Colors.orange,
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Archive Event?'),
                          content: Text(
                            'Are you sure you want to archive "$title"?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text(
                                'Archive',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          final batch = FirebaseFirestore.instance.batch();

                          batch.update(
                            FirebaseFirestore.instance
                                .collection('events')
                                .doc(eventId),
                            {
                              'status': 'archived',
                              'archivedAt': FieldValue.serverTimestamp(),
                            },
                          );

                          batch.set(
                            FirebaseFirestore.instance
                                .collection('room_assignments')
                                .doc(eventId),
                            {'status': 'archived'},
                            SetOptions(merge: true),
                          );

                          await batch.commit();

                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Event archived successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (error) {
                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to archive event: $error'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
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
    String title, {
    bool permanently = false,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          permanently ? 'Delete Event Permanently?' : 'Delete Event?',
        ),
        content: Text(
          permanently
              ? 'Are you sure you want to permanently delete "$title" '
                    'and its linked room assignment? This action cannot be undone.'
              : 'Are you sure you want to delete "$title"? '
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
            child: Text(permanently ? 'Delete Permanently' : 'Delete'),
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
        SnackBar(
          content: Text(
            permanently
                ? 'Event permanently deleted successfully!'
                : 'Event and room assignment deleted successfully!',
          ),
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
  final bool restoreAfterSave;

  const EventFormDialog({
    super.key,
    this.eventId,
    this.eventData,
    this.restoreAfterSave = false,
  });

  @override
  State<EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<EventFormDialog> {
  final _formKey = GlobalKey<FormState>();

  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  DateTime focusedDay = DateTime.now();

  Set<DateTime> unavailableDates = {};
  Set<DateTime> tentativeDates = {};
  // Room availability settings
  static const int operatingStartMinutes = 8 * 60;
  static const int operatingEndMinutes = 21 * 60;

  List<Map<String, dynamic>> selectedDateBookings = [];
  List<Map<String, dynamic>> selectedDatePendingBookings = [];

  List<Map<String, int>> availableTimeRanges = [];

  bool isLoadingDateAvailability = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted && selectedLocation != null) {
        await loadMonthlyAvailability(focusedDay);
        await loadSelectedDateAvailability();
      }
    });
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  int _toMinutes(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  String _formatMinutes(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;

    final time = TimeOfDay(hour: hour, minute: minute);
    return time.format(context);
  }

  void _calculateAvailableTimeRanges() {
    final bookings = [...selectedDateBookings];

    bookings.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

    availableTimeRanges.clear();

    int currentStart = operatingStartMinutes;

    for (final booking in bookings) {
      final start = booking['start'] as int;
      final end = booking['end'] as int;

      if (start > currentStart) {
        availableTimeRanges.add({'start': currentStart, 'end': start});
      }

      if (end > currentStart) {
        currentStart = end;
      }
    }

    if (currentStart < operatingEndMinutes) {
      availableTimeRanges.add({
        'start': currentStart,
        'end': operatingEndMinutes,
      });
    }

    availableTimeRanges.removeWhere(
      (range) => range['end']! <= range['start']!,
    );
  }

  bool _hasTimeOverlap(
    int existingStart,
    int existingEnd,
    int selectedStart,
    int selectedEnd,
  ) {
    return existingStart < selectedEnd && existingEnd > selectedStart;
  }

  Future<void> loadMonthlyAvailability(DateTime month) async {
    if (selectedLocation == null) return;

    try {
      final firestore = FirebaseFirestore.instance;

      final firstDay = DateTime(month.year, month.month, 1);
      final nextMonth = DateTime(month.year, month.month + 1, 1);

      final startTimestamp = Timestamp.fromDate(firstDay);
      final endTimestamp = Timestamp.fromDate(nextMonth);

      final assignmentsSnapshot = await firestore
          .collection('room_assignments')
          .where('date', isGreaterThanOrEqualTo: startTimestamp)
          .where('date', isLessThan: endTimestamp)
          .get();

      final activitiesSnapshot = await firestore
          .collection('club_activities')
          .where('date', isGreaterThanOrEqualTo: startTimestamp)
          .where('date', isLessThan: endTimestamp)
          .get();

      final classesSnapshot = await firestore
          .collection('classes')
          .where('status', isEqualTo: 'active')
          .get();

      final confirmed = <DateTime>{};
      final tentative = <DateTime>{};

      for (final assignment in assignmentsSnapshot.docs) {
        final data = assignment.data();

        if (data['roomName']?.toString() != selectedLocation) continue;
        if (data['status'] == 'archived' ||
            data['status'] == 'cancelled' ||
            data['status'] == 'rejected' ||
            data['status'] == 'pending') {
          continue;
        }

        final dateValue = data['date'];
        if (dateValue is! Timestamp) continue;

        confirmed.add(_dateOnly(dateValue.toDate()));
      }

      for (final activity in activitiesSnapshot.docs) {
        final data = activity.data();

        if (data['roomName']?.toString() != selectedLocation) continue;

        final dateValue = data['date'];
        if (dateValue is! Timestamp) continue;

        final date = _dateOnly(dateValue.toDate());

        if (data['status'] == 'approved') {
          confirmed.add(date);
        } else if (data['status'] == 'pending') {
          tentative.add(date);
        }
      }

      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];

      for (final classDoc in classesSnapshot.docs) {
        final schedules = classDoc.data()['schedules'];

        if (schedules is! List) continue;

        for (final schedule in schedules) {
          if (schedule is! Map) continue;

          if (schedule['roomName']?.toString() != selectedLocation) {
            continue;
          }

          final day = schedule['dayOfWeek']?.toString();

          if (!weekdays.contains(day)) continue;

          for (
            DateTime date = firstDay;
            date.isBefore(nextMonth);
            date = date.add(const Duration(days: 1))
          ) {
            if (weekdays[date.weekday - 1] == day) {
              confirmed.add(_dateOnly(date));
            }
          }
        }
      }

      if (!mounted) return;

      setState(() {
        unavailableDates = confirmed;
        tentativeDates = tentative;
      });
    } catch (error) {
      debugPrint('Failed to load monthly availability: $error');
    }
  }

  Future<void> loadSelectedDateAvailability() async {
    if (selectedLocation == null) return;

    setState(() {
      isLoadingDateAvailability = true;
      selectedDateBookings.clear();
      selectedDatePendingBookings.clear();
      availableTimeRanges.clear();
    });

    final firestore = FirebaseFirestore.instance;

    final dateStart = _dateOnly(selectedDate);
    final nextDate = dateStart.add(const Duration(days: 1));

    final bookings = <Map<String, dynamic>>[];
    final pendingBookings = <Map<String, dynamic>>[];

    void addBooking(Map<String, dynamic> data, String title, String status) {
      final start = data['startTimeMinutes'];
      final end = data['endTimeMinutes'];

      if (start is! num || end is! num) return;

      final startMinutes = start.toInt();
      final endMinutes = end.toInt();

      if (endMinutes <= operatingStartMinutes ||
          startMinutes >= operatingEndMinutes ||
          endMinutes <= startMinutes) {
        return;
      }

      final booking = <String, dynamic>{
        'start': startMinutes
            .clamp(operatingStartMinutes, operatingEndMinutes)
            .toInt(),
        'end': endMinutes
            .clamp(operatingStartMinutes, operatingEndMinutes)
            .toInt(),
      };

      if (status == 'approved') {
        bookings.add(booking);
      } else if (status == 'pending') {
        pendingBookings.add(booking);
      }
    }

    try {
      // 1. Confirmed Event room assignments
      final assignmentsSnapshot = await firestore
          .collection('room_assignments')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('date', isLessThan: Timestamp.fromDate(nextDate))
          .get();

      for (final doc in assignmentsSnapshot.docs) {
        if (isEditing && doc.id == widget.eventId) continue;

        final data = doc.data();

        if (data['roomName']?.toString() != selectedLocation) continue;

        final status = data['status']?.toString().toLowerCase() ?? '';

        if (['archived', 'cancelled', 'rejected', 'pending'].contains(status)) {
          continue;
        }

        addBooking(
          data,
          data['eventTitle']?.toString() ?? 'Campus Event',
          'approved',
        );
      }

      // 2. Club Activities
      final activitiesSnapshot = await firestore
          .collection('club_activities')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('date', isLessThan: Timestamp.fromDate(nextDate))
          .get();

      for (final doc in activitiesSnapshot.docs) {
        final data = doc.data();

        if (data['roomName']?.toString() != selectedLocation) continue;

        final status = data['status']?.toString().toLowerCase() ?? '';

        if (status != 'approved' && status != 'pending') continue;

        addBooking(
          data,
          data['activityTitle']?.toString() ?? 'Club Activity',
          status,
        );
      }

      // 3. Active class schedules
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

      final selectedDay = weekdays[selectedDate.weekday - 1];

      for (final classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final schedules = classData['schedules'];

        if (schedules is! List) continue;

        for (final schedule in schedules) {
          if (schedule is! Map) continue;

          if (schedule['roomName']?.toString() != selectedLocation) continue;
          if (schedule['dayOfWeek']?.toString() != selectedDay) continue;

          final start = schedule['startTimeMinutes'];
          final end = schedule['endTimeMinutes'];

          if (start is! num || end is! num) continue;

          addBooking(
            {'startTimeMinutes': start, 'endTimeMinutes': end},
            classData['subjectName']?.toString() ?? 'Class Schedule',
            'approved',
          );
        }
      }

      if (!mounted) return;

      setState(() {
        selectedDateBookings = bookings;
        selectedDatePendingBookings = pendingBookings;

        _calculateAvailableTimeRanges();

        isLoadingDateAvailability = false;
      });
    } catch (error) {
      debugPrint('Failed to load selected date availability: $error');

      if (!mounted) return;

      setState(() {
        isLoadingDateAvailability = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load availability: $error')),
      );
    }
  }

  Future<void> selectDate() async {
    DateTime dialogFocusedDay = focusedDay;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            return AlertDialog(
              title: const Text('Check Date Availability'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TableCalendar<String>(
                        firstDay: DateTime(2020),
                        lastDay: DateTime(2035),
                        focusedDay: dialogFocusedDay,
                        selectedDayPredicate: (day) =>
                            isSameDay(day, selectedDate),
                        eventLoader: (day) {
                          final date = _dateOnly(day);

                          if (unavailableDates.contains(date)) {
                            return ['Confirmed booking'];
                          }

                          if (tentativeDates.contains(date)) {
                            return ['Pending activity'];
                          }

                          return [];
                        },
                        onDaySelected: (selected, focused) {
                          setState(() {
                            selectedDate = _dateOnly(selected);
                            focusedDay = focused;

                            selectedDateBookings.clear();
                            selectedDatePendingBookings.clear();
                            availableTimeRanges.clear();
                          });

                          Navigator.pop(dialogContext);

                          loadSelectedDateAvailability();
                        },
                        onPageChanged: (focused) {
                          dialogFocusedDay = focused;
                          focusedDay = focused;

                          updateDialog(() {});

                          loadMonthlyAvailability(focused);
                        },
                        calendarStyle: const CalendarStyle(
                          todayDecoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: BoxDecoration(
                            color: Colors.indigo,
                            shape: BoxShape.circle,
                          ),
                          markerDecoration: BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                        ),
                        calendarBuilders: CalendarBuilders(
                          markerBuilder: (context, day, events) {
                            if (events.isEmpty) return null;

                            final date = _dateOnly(day);

                            final color = unavailableDates.contains(date)
                                ? Colors.red
                                : Colors.orange;

                            return Positioned(
                              bottom: 4,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _AvailabilityLegend(
                            color: Colors.red,
                            label: 'Confirmed booking',
                          ),
                          _AvailabilityLegend(
                            color: Colors.orange,
                            label: 'Pending activity',
                          ),
                          _AvailabilityLegend(
                            color: Colors.blue,
                            label: 'Today',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'A marked date may still have other available '
                        'time slots. Select a date to continue.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
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

    // PREVENT PREVIOUS DATES
    final today = DateTime.now();
    final currentDate = DateTime(today.year, today.month, today.day);
    final eventDateOnly = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

    if (eventDateOnly.isBefore(currentDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot schedule an event on a previous date.'),
          backgroundColor: Colors.red,
        ),
      );
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
        batch.update(eventRef, {
          ...eventData,
          if (widget.restoreAfterSave) ...{
            'status': 'published',
            'archivedAt': FieldValue.delete(),
          },
        });
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
        'status': 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.restoreAfterSave
                ? 'Event updated and published successfully!'
                : isEditing
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
      title: Text(
        widget.restoreAfterSave
            ? 'Edit and Publish Event'
            : isEditing
            ? 'Edit Event'
            : 'Add New Event',
      ),

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
                    : (value) async {
                        setState(() {
                          selectedLocation = value;

                          unavailableDates.clear();
                          tentativeDates.clear();

                          selectedDateBookings.clear();
                          selectedDatePendingBookings.clear();
                          availableTimeRanges.clear();
                        });

                        if (value != null) {
                          await loadMonthlyAvailability(focusedDay);
                          await loadSelectedDateAvailability();
                        }
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

              // ROOM AVAILABILITY
              if (selectedLocation != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.meeting_room, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Room Availability',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Text(
                            '8:00 AM – 9:00 PM',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (isLoadingDateAvailability)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else ...[
                        const Text(
                          'Available Time Slots',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),

                        if (availableTimeRanges.isEmpty)
                          const Text(
                            'No available time slots for this date.',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: availableTimeRanges.map((range) {
                              return Chip(
                                avatar: const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 16,
                                ),
                                label: Text(
                                  '${_formatMinutes(range['start']!)} – '
                                  '${_formatMinutes(range['end']!)}',
                                ),
                              );
                            }).toList(),
                          ),

                        if (selectedDatePendingBookings.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Pending Requests',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 8),

                          ...selectedDatePendingBookings.map((booking) {
                            final title = booking['title']?.toString();

                            final displayTitle =
                                title == null ||
                                    title.trim().isEmpty ||
                                    title.toLowerCase() == 'null'
                                ? 'Club Activity'
                                : title;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$displayTitle · '
                                      '${_formatMinutes(booking['start'])} – '
                                      '${_formatMinutes(booking['end'])}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ],
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
              : Text(
                  widget.restoreAfterSave
                      ? 'Save and Publish'
                      : isEditing
                      ? 'Update Event'
                      : 'Save Event',
                ),
        ),
      ],
    );
  }
}

class _AvailabilityLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _AvailabilityLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class ArchivedEventsPage extends StatelessWidget {
  const ArchivedEventsPage({super.key});

  Future<void> restoreEvent(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> event,
  ) async {
    final title = event.data()?['title'] ?? 'this event';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore Event?'),
        content: Text(
          'Are you sure you want to restore "$title"? '
          'It will appear again in the Events page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.update(event.reference, {
        'status': FieldValue.delete(),
        'archivedAt': FieldValue.delete(),
      });

      final assignmentRef = FirebaseFirestore.instance
          .collection('room_assignments')
          .doc(event.id);

      batch.update(assignmentRef, {'status': FieldValue.delete()});

      await batch.commit();

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event restored successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restore event: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

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
          if (snapshot.hasError) {
            return const Center(
              child: Text('Something went wrong loading archived events.'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final archivedEvents = snapshot.data?.docs ?? [];

          if (archivedEvents.isEmpty) {
            return const Center(child: Text('No archived events yet.'));
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: archivedEvents.map((event) {
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
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(
                    Icons.archive_outlined,
                    color: Colors.blue,
                  ),
                  title: Text(
                    title.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('$dateText\n$location'),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit and Publish',
                        icon: const Icon(Icons.restore, color: Colors.green),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (dialogContext) => EventFormDialog(
                              eventId: event.id,
                              eventData: data,
                              restoreAfterSave: true,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete Permanently',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () async {
                          await EventsPage().deleteEvent(
                            context,
                            event.id,
                            title.toString(),
                            permanently: true,
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(title.toString()),
                        content: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Date: $dateText'),
                              const SizedBox(height: 8),
                              Text('Location: $location'),
                              const SizedBox(height: 12),
                              Text(description.toString()),
                            ],
                          ),
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
            }).toList(),
          );
        },
      ),
    );
  }
}
