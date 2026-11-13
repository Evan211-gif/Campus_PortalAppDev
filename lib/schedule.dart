import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime _focusedDate = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  late Future<List<Map<String, dynamic>>> _classesFuture;
  late Future<Map<DateTime, List<Map<String, dynamic>>>> _holidaysFuture;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Color primaryColor = Color(0xFF245A91);
  static const Color classColor = Color(0xFFE67E22);
  static const Color eventColor = Color(0xFF2878D0);
  static const Color holidayColor = Color(0xFF269B59);
  static const Color clubActivityColor = Color(0xFF8E44AD);

  int _holidaysFutureYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();

    _classesFuture = _loadClassSchedules();
    _holidaysFuture = _loadHolidays(_focusedDate.year);
  }

  // DATE HELPERS

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _dayName(int weekday) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return days[weekday - 1];
  }

  // LOAD STUDENT'S ASSIGNED CLASSES

  Future<List<Map<String, dynamic>>> _loadClassSchedules() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return [];
    }

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final role = userDoc.data()?['role']?.toString();

    final List<DocumentSnapshot<Map<String, dynamic>>> classDocs = [];

    if (role == 'teacher') {
      // Teachers load classes assigned to their account.
      final snapshot = await _db
          .collection('classes')
          .where('teacherId', isEqualTo: user.uid)
          .get();

      classDocs.addAll(snapshot.docs);
    } else {
      // Students and Admin retain the existing enrollment-based behavior.
      final enrollmentSnapshot = await _db
          .collection('class_enrollments')
          .where('studentId', isEqualTo: user.uid)
          .get();

      for (final enrollment in enrollmentSnapshot.docs) {
        final classId = enrollment.data()['classId'];

        if (classId == null) continue;

        final classDoc = await _db
            .collection('classes')
            .doc(classId.toString())
            .get();

        if (classDoc.exists) {
          classDocs.add(classDoc);
        }
      }
    }

    final List<Map<String, dynamic>> schedules = [];

    for (final classDoc in classDocs) {
      final classData = classDoc.data();

      if (classData == null) continue;
      if (classData['status'] != 'active') continue;

      final rawSchedules = classData['schedules'];

      if (rawSchedules is! List) continue;

      for (final item in rawSchedules) {
        if (item is! Map) continue;

        final schedule = Map<String, dynamic>.from(item);

        schedules.add({
          'type': 'class',
          'title': classData['subjectName'] ?? 'Untitled Class',
          'subjectCode': classData['subjectCode'] ?? '',
          'dayOfWeek': schedule['dayOfWeek'] ?? '',
          'startTimeMinutes': schedule['startTimeMinutes'] ?? 0,
          'endTimeMinutes': schedule['endTimeMinutes'] ?? 0,
          'roomName': schedule['roomName'] ?? 'Room not specified',
        });
      }
    }

    return schedules;
  }

  // LOAD PHILIPPINE PUBLIC HOLIDAYS

  Future<Map<DateTime, List<Map<String, dynamic>>>> _loadHolidays(
    int year,
  ) async {
    try {
      final url = Uri.parse(
        'https://date.nager.at/api/v3/PublicHolidays/$year/PH',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Unable to load holidays.');
      }

      final List<dynamic> results = jsonDecode(response.body);

      final Map<DateTime, List<Map<String, dynamic>>> holidayMap = {};

      for (final item in results) {
        final date = DateTime.parse(item['date']);
        final key = _dateOnly(date);

        holidayMap.putIfAbsent(key, () => []);

        holidayMap[key]!.add({
          'type': 'holiday',
          'title': item['localName'] ?? item['name'] ?? 'Holiday',
        });
      }

      return holidayMap;
    } catch (error) {
      debugPrint('Holiday loading error: $error');
      return {};
    }
  }

  // FORMAT TIME

  String _formatTime(dynamic minutes) {
    if (minutes is! int || minutes < 0 || minutes >= 1440) {
      return 'Time unavailable';
    }

    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

    return time.format(context);
  }

  // GET ACTIVITIES FOR A SELECTED DATE

  List<Map<String, dynamic>> _getEntriesForDay(
    DateTime day,
    List<Map<String, dynamic>> classSchedules,
    Map<DateTime, List<Map<String, dynamic>>> eventMap,
    Map<DateTime, List<Map<String, dynamic>>> holidayMap,
    Map<DateTime, List<Map<String, dynamic>>> activityMap,
  ) {
    final entries = <Map<String, dynamic>>[];

    final selectedDayName = _dayName(day.weekday);

    // RECURRING REGULAR CLASSES

    for (final schedule in classSchedules) {
      if (schedule['dayOfWeek'] == selectedDayName) {
        entries.add(schedule);
      }
    }

    final dateKey = _dateOnly(day);

    // CAMPUS EVENTS

    entries.addAll(eventMap[dateKey] ?? []);

    // PHILIPPINE HOLIDAYS

    entries.addAll(holidayMap[dateKey] ?? []);

    // APPROVED CLUB ACTIVITIES

    entries.addAll(activityMap[dateKey] ?? []);

    // SORT BY START TIME
    // Holidays without a time appear first.

    entries.sort((a, b) {
      final aTime = a['startTimeMinutes'] is int
          ? a['startTimeMinutes'] as int
          : -1;

      final bTime = b['startTimeMinutes'] is int
          ? b['startTimeMinutes'] as int
          : -1;

      return aTime.compareTo(bTime);
    });

    return entries;
  }

  // ACTIVITY MARKERS

  Widget _buildMarkers(List<Map<String, dynamic>> entries) {
    final hasClass = entries.any((e) => e['type'] == 'class');
    final hasEvent = entries.any((e) => e['type'] == 'event');
    final hasHoliday = entries.any((e) => e['type'] == 'holiday');
    final hasClubActivity = entries.any((e) => e['type'] == 'club_activity');

    if (!hasClass && !hasEvent && !hasHoliday && !hasClubActivity) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasClass) _marker(classColor),
          if (hasEvent) _marker(eventColor),
          if (hasHoliday) _marker(holidayColor),
          if (hasClubActivity) _marker(clubActivityColor),
        ],
      ),
    );
  }

  Widget _marker(Color color) {
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  // ACTIVITY CARD

  Widget _buildActivityCard(Map<String, dynamic> entry) {
    final type = entry['type'];

    final Color color;
    final IconData icon;
    final String category;

    if (type == 'class') {
      color = classColor;
      icon = Icons.school;
      category = 'Regular Class';
    } else if (type == 'event') {
      color = eventColor;
      icon = Icons.event;
      category = 'Campus Event';
    } else if (type == 'club_activity') {
      color = clubActivityColor;
      icon = Icons.groups;
      category = 'Club Activity';
    } else {
      color = holidayColor;
      icon = Icons.celebration;
      category = 'Philippine Holiday';
    }

    final startTime = entry['startTimeMinutes'];
    final endTime = entry['endTimeMinutes'];

    String timeText = 'All day';

    if (type != 'holiday' && startTime is int && endTime is int) {
      timeText = '${_formatTime(startTime)} - ${_formatTime(endTime)}';
    }

    final location = type == 'class' || type == 'club_activity'
        ? entry['roomName']
        : entry['location'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    entry['title']?.toString() ?? 'Untitled Activity',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (type == 'class' &&
                      entry['subjectCode'].toString().isNotEmpty)
                    Text(
                      entry['subjectCode'].toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),

                  if (type == 'club_activity')
                    Text(
                      entry['clubName']?.toString() ?? 'Unknown Club',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),

                  const SizedBox(height: 7),

                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 15,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          timeText,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  if (type != 'holiday')
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 15,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              location?.toString() ?? 'Location not specified',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MAIN PAGE

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Schedule')),
        body: const Center(child: Text('Please log in to view your schedule.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),

      appBar: AppBar(
        title: const Text(
          'My Schedule',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _classesFuture,
        builder: (context, classSnapshot) {
          if (classSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (classSnapshot.hasError) {
            return const Center(
              child: Text('Unable to load your class schedules.'),
            );
          }

          final classSchedules = classSnapshot.data ?? [];

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('events').snapshots(),
            builder: (context, eventSnapshot) {
              if (eventSnapshot.hasError) {
                return const Center(
                  child: Text('Unable to load campus events.'),
                );
              }

              if (eventSnapshot.connectionState == ConnectionState.waiting &&
                  !eventSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final eventMap = <DateTime, List<Map<String, dynamic>>>{};

              for (final doc in eventSnapshot.data?.docs ?? []) {
                final data = doc.data();

                if (data['status'] == 'archived') continue;
                if (data['date'] is! Timestamp) continue;

                final date = _dateOnly((data['date'] as Timestamp).toDate());

                eventMap.putIfAbsent(date, () => []);

                eventMap[date]!.add({
                  'type': 'event',
                  'title': data['title'] ?? 'Campus Event',
                  'startTimeMinutes': data['startTimeMinutes'],
                  'endTimeMinutes': data['endTimeMinutes'],
                  'location': data['location'] ?? 'Location not specified',
                });
              }

              // APPROVED CLUB ACTIVITIES

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db
                    .collection('club_activities')
                    .where('status', isEqualTo: 'approved')
                    .snapshots(),
                builder: (context, activitySnapshot) {
                  if (activitySnapshot.hasError) {
                    return const Center(
                      child: Text('Unable to load club activities.'),
                    );
                  }

                  if (activitySnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !activitySnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final activityMap = <DateTime, List<Map<String, dynamic>>>{};

                  for (final doc in activitySnapshot.data?.docs ?? []) {
                    final data = doc.data();

                    if (data['status'] != 'approved') continue;
                    if (data['date'] is! Timestamp) continue;

                    final date = _dateOnly(
                      (data['date'] as Timestamp).toDate(),
                    );

                    activityMap.putIfAbsent(date, () => []);

                    activityMap[date]!.add({
                      'type': 'club_activity',
                      'title': data['activityTitle'] ?? 'Club Activity',
                      'clubName': data['clubName'] ?? 'Unknown Club',
                      'startTimeMinutes': data['startTimeMinutes'],
                      'endTimeMinutes': data['endTimeMinutes'],
                      'roomName': data['roomName'] ?? 'Room not specified',
                    });
                  }

                  // PHILIPPINE HOLIDAYS

                  return FutureBuilder<
                    Map<DateTime, List<Map<String, dynamic>>>
                  >(
                    future: _holidaysFuture,
                    builder: (context, holidaySnapshot) {
                      final holidayMap = holidaySnapshot.data ?? {};

                      final selectedEntries = _getEntriesForDay(
                        _selectedDate,
                        classSchedules,
                        eventMap,
                        holidayMap,
                        activityMap,
                      );

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // CALENDAR

                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    TableCalendar<Map<String, dynamic>>(
                                      firstDay: DateTime(2020),
                                      lastDay: DateTime(2035),
                                      focusedDay: _focusedDate,

                                      selectedDayPredicate: (day) =>
                                          isSameDay(day, _selectedDate),

                                      eventLoader: (day) {
                                        return _getEntriesForDay(
                                          day,
                                          classSchedules,
                                          eventMap,
                                          holidayMap,
                                          activityMap,
                                        );
                                      },

                                      onDaySelected: (selected, focused) {
                                        setState(() {
                                          _selectedDate = selected;
                                          _focusedDate = focused;
                                        });
                                      },

                                      onPageChanged: (focused) {
                                        setState(() {
                                          _focusedDate = focused;

                                          if (_holidaysFutureYear !=
                                              focused.year) {
                                            _holidaysFutureYear = focused.year;

                                            _holidaysFuture = _loadHolidays(
                                              focused.year,
                                            );
                                          }
                                        });
                                      },

                                      calendarStyle: const CalendarStyle(
                                        selectedDecoration: BoxDecoration(
                                          color: primaryColor,
                                          shape: BoxShape.circle,
                                        ),
                                        todayDecoration: BoxDecoration(
                                          color: Colors.black26,
                                          shape: BoxShape.circle,
                                        ),
                                        outsideDaysVisible: false,
                                        markersMaxCount: 0,
                                      ),

                                      headerStyle: const HeaderStyle(
                                        formatButtonVisible: false,
                                        titleCentered: true,
                                      ),

                                      calendarBuilders:
                                          CalendarBuilders<
                                            Map<String, dynamic>
                                          >(
                                            markerBuilder:
                                                (context, day, entries) {
                                                  if (entries.isEmpty) {
                                                    return null;
                                                  }

                                                  return _buildMarkers(entries);
                                                },
                                          ),
                                    ),

                                    const SizedBox(height: 12),

                                    // LEGEND
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 16,
                                      runSpacing: 8,
                                      children: const [
                                        _LegendItem(
                                          color: classColor,
                                          label: 'Classes',
                                        ),
                                        _LegendItem(
                                          color: eventColor,
                                          label: 'Events',
                                        ),
                                        _LegendItem(
                                          color: holidayColor,
                                          label: 'Holidays',
                                        ),
                                        _LegendItem(
                                          color: clubActivityColor,
                                          label: 'Club Activities',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 22),

                            // SELECTED DATE
                            Text(
                              'Activities on ${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 12),

                            if (holidaySnapshot.connectionState ==
                                ConnectionState.waiting)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (selectedEntries.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Column(
                                  children: [
                                    Icon(
                                      Icons.event_busy,
                                      size: 40,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'No activities scheduled for this day.',
                                      style: TextStyle(color: Colors.black54),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            else
                              ...selectedEntries.map(_buildActivityCard),

                            const SizedBox(height: 20),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// LEGEND ITEM

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
