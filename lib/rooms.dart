import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'dart:async';

class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  String _selectedFilter = 'All';
  String _searchQuery = '';
  DateTime _selectedDate = DateTime.now();
  Timer? _availabilityTimer;

  final List<String> _rooms = [
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

  @override
  void initState() {
    super.initState();

    _availabilityTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  int _currentMinutes() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  String _formatTime(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
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

  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  List<Map<String, dynamic>> _getBookings({
    required String roomName,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> classes,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> events,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> activities,
  }) {
    final selectedDay = _selectedDate;
    final selectedDayName = _dayName(selectedDay.weekday);
    final bookings = <Map<String, dynamic>>[];

    // REGULAR CLASS SCHEDULES
    for (final classDoc in classes) {
      final data = classDoc.data();

      if (data['status'] != 'active') continue;

      final schedules = data['schedules'];

      if (schedules is! List) continue;

      for (final schedule in schedules) {
        if (schedule is! Map) continue;

        final scheduleData = Map<String, dynamic>.from(schedule);

        if (scheduleData['dayOfWeek'] != selectedDayName ||
            scheduleData['roomName'] != roomName) {
          continue;
        }

        final start = scheduleData['startTimeMinutes'];
        final end = scheduleData['endTimeMinutes'];

        if (start is! num || end is! num) continue;

        bookings.add({
          'title': data['subjectName'] ?? 'Regular Class',
          'type': 'Regular Class',
          'start': start.toInt(),
          'end': end.toInt(),
        });
      }
    }

    // CAMPUS EVENTS
    for (final eventDoc in events) {
      final data = eventDoc.data();

      if (data['status'] == 'archived') continue;

      final eventDate = data['date'];
      if (eventDate is! Timestamp) continue;

      if (!_isSameDate(eventDate.toDate(), selectedDay)) continue;

      if (data['location'] != roomName) continue;

      final start = data['startTimeMinutes'];
      final end = data['endTimeMinutes'];

      if (start is! num || end is! num) continue;

      bookings.add({
        'title': data['title'] ?? 'Campus Event',
        'type': 'Campus Event',
        'start': start.toInt(),
        'end': end.toInt(),
      });
    }

    // APPROVED CLUB ACTIVITIES
    for (final activityDoc in activities) {
      final data = activityDoc.data();

      if (data['status'] != 'approved') continue;

      final activityDate = data['date'];
      if (activityDate is! Timestamp) continue;

      if (!_isSameDate(activityDate.toDate(), selectedDay)) continue;

      if (data['roomName'] != roomName) continue;

      final start = data['startTimeMinutes'];
      final end = data['endTimeMinutes'];

      if (start is! num || end is! num) continue;

      bookings.add({
        'title': data['activityTitle'] ?? 'Club Activity',
        'clubName': data['clubName'] ?? 'Unknown Club',
        'type': 'Club Activity',
        'start': start.toInt(),
        'end': end.toInt(),
      });
    }

    bookings.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

    return bookings;
  }

  bool _isOccupied(List<Map<String, dynamic>> bookings) {
    final today = DateTime.now();

    // For future or past dates, show whether the room has bookings.
    if (!_isSameDate(_selectedDate, today)) {
      return bookings.isNotEmpty;
    }

    // For today, check the actual current time.
    final currentTime = _currentMinutes();

    return bookings.any((booking) {
      final start = booking['start'] as int;
      final end = booking['end'] as int;

      return currentTime >= start && currentTime < end;
    });
  }

  String _getNextBooking(List<Map<String, dynamic>> bookings) {
    if (bookings.isEmpty) {
      return 'No bookings scheduled';
    }

    final isToday = _isSameDate(_selectedDate, DateTime.now());

    if (!isToday) {
      final firstBooking = bookings.first;

      return 'First booking: ${_formatTime(firstBooking['start'])}';
    }

    final currentTime = _currentMinutes();

    for (final booking in bookings) {
      final start = booking['start'] as int;

      if (start > currentTime) {
        return 'Next: ${booking['title']} at ${_formatTime(start)}';
      }
    }

    return 'No upcoming bookings today';
  }

  void _openRoomDetails(String roomName, List<Map<String, dynamic>> bookings) {
    final isToday = _isSameDate(_selectedDate, DateTime.now());
    final occupied = _isOccupied(bookings);

    final statusText = isToday
        ? (occupied ? 'Currently Occupied' : 'Currently Available')
        : (bookings.isNotEmpty ? 'Has Bookings' : 'No Bookings');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  roomName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: occupied ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: occupied
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                Text(
                  'Bookings for ${MaterialLocalizations.of(context).formatMediumDate(_selectedDate)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                if (bookings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No bookings scheduled for this date.'),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: bookings.length,
                      separatorBuilder: (_, _) => const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final booking = bookings[index];

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.access_time, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking['title'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatTime(booking['start'])} - '
                                    '${_formatTime(booking['end'])}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    booking['type'] == 'Club Activity'
                                        ? 'Club: ${booking['clubName']}'
                                        : booking['type'],
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoomList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classes,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> events,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> activities,
  ) {
    final filteredRooms = _rooms.where((room) {
      final matchesSearch = room.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );

      final bookings = _getBookings(
        roomName: room,
        classes: classes,
        events: events,
        activities: activities,
      );

      final isToday = _isSameDate(_selectedDate, DateTime.now());
      final occupied = _isOccupied(bookings);

      final matchesFilter =
          _selectedFilter == 'All' ||
          (_selectedFilter == 'Available' &&
              (isToday ? !occupied : bookings.isEmpty)) ||
          (_selectedFilter == 'Occupied' &&
              (isToday ? occupied : bookings.isNotEmpty));

      return matchesSearch && matchesFilter;
    }).toList();

    if (filteredRooms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: Text('No rooms found.')),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredRooms.length,
      itemBuilder: (context, index) {
        final room = filteredRooms[index];

        final bookings = _getBookings(
          roomName: room,
          classes: classes,
          events: events,
          activities: activities,
        );

        final isToday = _isSameDate(_selectedDate, DateTime.now());
        final occupied = _isOccupied(bookings);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openRoomDetails(room, bookings),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.meeting_room, color: Colors.blue),
                  ),
                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          isToday
                              ? (occupied
                                    ? 'Currently in use'
                                    : _getNextBooking(bookings))
                              : (bookings.isNotEmpty
                                    ? '${bookings.length} booking(s) scheduled'
                                    : 'No bookings scheduled'),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: occupied
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isToday
                          ? (occupied ? 'Occupied' : 'Available')
                          : (bookings.isNotEmpty
                                ? 'Has Bookings'
                                : 'No Bookings'),
                      style: TextStyle(
                        color: occupied
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Find a Room',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF245A91),
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFF245A91),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('classes').snapshots(),
        builder: (context, classSnapshot) {
          if (classSnapshot.hasError) {
            return const Center(child: Text('Unable to load class schedules.'));
          }

          if (!classSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('events').snapshots(),
            builder: (context, eventSnapshot) {
              if (eventSnapshot.hasError) {
                return const Center(
                  child: Text('Unable to load campus events.'),
                );
              }

              if (!eventSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

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

                  if (!activitySnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final classes = classSnapshot.data!.docs;
                  final events = eventSnapshot.data!.docs;
                  final activities = activitySnapshot.data!.docs;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Find a Room',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Check room availability and scheduled bookings.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // DATE PICKER
                        InkWell(
                          onTap: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );

                            if (pickedDate != null) {
                              setState(() {
                                _selectedDate = pickedDate;
                              });
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    MaterialLocalizations.of(context)
                                        .formatMediumDate(_selectedDate),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search rooms...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Wrap(
                          spacing: 8,
                          children: ['All', 'Available', 'Occupied'].map((
                            filter,
                          ) {
                            final selected = _selectedFilter == filter;

                            return ChoiceChip(
                              label: Text(filter),
                              selected: selected,
                              onSelected: (_) {
                                setState(() {
                                  _selectedFilter = filter;
                                });
                              },
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Campus Rooms',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${_rooms.length} rooms',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        _buildRoomList(classes, events, activities),
                      ],
                    ),
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
