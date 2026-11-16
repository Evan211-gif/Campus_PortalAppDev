import 'login.dart';
import 'landing_page.dart';
import 'profile.dart';
import 'rooms.dart';
import 'schedule.dart';
import 'class_management.dart';
import 'user_management.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';

import 'firebase_options.dart';
import 'events.dart';
import 'clubs.dart';
import 'announcements.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('FLUTTER FIREBASE PROJECT: ${Firebase.app().options.projectId}');

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedIndex = 0;
  final ValueNotifier<DateTime> _selectedDate = ValueNotifier<DateTime>(
    DateTime.now(),
  );

  DateTime _focusedDate = DateTime.now();

  int _loadedHolidayYear = DateTime.now().year;

  final ValueNotifier<Map<DateTime, List<Map<String, dynamic>>>>
  _holidaysByDate = ValueNotifier({});

  final ValueNotifier<bool> _holidaysLoading = ValueNotifier(false);

  late final Stream<User?> _authStream = FirebaseAuth.instance
      .authStateChanges()
      .map((user) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          }
        });

        return user;
      });

  @override
  void initState() {
    super.initState();
    _loadHolidays(_loadedHolidayYear);
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  Future<void> _loadHolidays(int year) async {
    _holidaysLoading.value = true;

    try {
      final url = Uri.parse(
        'https://date.nager.at/api/v3/PublicHolidays/$year/PH',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Unable to load Philippine holidays.');
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

      if (!mounted) return;

      _holidaysByDate.value = holidayMap;
    } catch (error) {
      debugPrint('Holiday loading error: $error');
    } finally {
      _holidaysLoading.value = false;
    }
  }

  Widget _buildDashboardSearch(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final role = snapshot.data?.data()?['role'];
        final isAdmin = role == 'admin';

        final features = [
          {'name': 'Schedule', 'icon': Icons.calendar_month, 'admin': false},
          {'name': 'Events', 'icon': Icons.event, 'admin': false},
          {'name': 'Announcements', 'icon': Icons.campaign, 'admin': false},
          {'name': 'Clubs', 'icon': Icons.groups, 'admin': false},
          {'name': 'Rooms', 'icon': Icons.meeting_room, 'admin': false},
          {'name': 'Profile', 'icon': Icons.person, 'admin': false},
          {'name': 'Class Management', 'icon': Icons.school, 'admin': true},
          {
            'name': 'Club Activity Requests',
            'icon': Icons.event_available,
            'admin': true,
          },
        ];

        final results = features.where((feature) {
          final name = feature['name'] as String;
          final adminOnly = feature['admin'] as bool;

          return name.toLowerCase().contains(_searchQuery.toLowerCase()) &&
              (!adminOnly || isAdmin);
        }).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.trim();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'What are you looking for?',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFF245A91),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF5F7FA),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Color(0xFFDCE8F4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Color(0xFFDCE8F4)),
                  ),
                ),
              ),

              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No matching features found.'),
                  )
                else
                  ...results.map((feature) {
                    final name = feature['name'] as String;

                    return ListTile(
                      dense: true,
                      leading: Icon(
                        feature['icon'] as IconData,
                        color: const Color(0xFF245A91),
                      ),
                      title: Text(name),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Widget? page;

                        switch (name) {
                          case 'Schedule':
                            page = const SchedulePage();
                            break;
                          case 'Events':
                            page = const EventsPage();
                            break;
                          case 'Announcements':
                            page = const AnnouncementsPage();
                            break;
                          case 'Clubs':
                            page = const ClubsPage();
                            break;
                          case 'Rooms':
                            page = const RoomsPage();
                            break;
                          case 'Profile':
                            page = const ProfilePage();
                            break;
                          case 'Class Management':
                            page = const ClassManagementPage();
                            break;
                          case 'Club Activity Requests':
                            page = const ClubActivityApprovalPage();
                            break;
                        }

                        if (page != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => page!),
                          );
                        }
                      },
                    );
                  }),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationDrawer(BuildContext context) {
    return Drawer(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final userData = snapshot.data?.data();
          final role = userData?['role'];
          final name = userData?['name'] ?? 'Campus User';
          final isAdmin = role == 'admin';

          void openPage(Widget page) {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => page));
          }

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Color(0xFF245A91)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Image.asset('assets/aces_logo.png', height: 65),
                    const SizedBox(height: 10),
                    Text(
                      name.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      role?.toString().toUpperCase() ?? '',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('Dashboard'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Schedule'),
                onTap: () => openPage(const SchedulePage()),
              ),
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Events'),
                onTap: () => openPage(const EventsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.campaign),
                title: const Text('Announcements'),
                onTap: () => openPage(const AnnouncementsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.groups),
                title: const Text('Clubs'),
                onTap: () => openPage(const ClubsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.meeting_room),
                title: const Text('Rooms'),
                onTap: () => openPage(const RoomsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                onTap: () => openPage(const ProfilePage()),
              ),
              if (isAdmin) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.school),
                  title: const Text('Class Management'),
                  onTap: () => openPage(const ClassManagementPage()),
                ),
                ListTile(
                  leading: const Icon(Icons.event_available),
                  title: const Text('Club Activity Requests'),
                  onTap: () => openPage(const ClubActivityApprovalPage()),
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout'),
                onTap: () async {
                  Navigator.pop(context);

                  setState(() {
                    _selectedIndex = 0;
                  });

                  await FirebaseAuth.instance.signOut();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF245A91),
          primary: const Color(0xFF245A91),
          secondary: const Color(0xFF2878D0),
          surface: Colors.white,
          error: const Color(0xFFC73535),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF245A91),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF245A91),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDCE8F4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDCE8F4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF245A91), width: 2),
          ),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF245A91),
        ),
      ),

      home: StreamBuilder<User?>(
        stream: _authStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.data == null) {
            return const LandingPage();
          }

          return Scaffold(
            backgroundColor: Colors.white,

            body: IndexedStack(
              index: _selectedIndex,
              children: [
                Scaffold(
                  backgroundColor: Colors.white,
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        // CAMPUS HEADER
                        Container(
                          height: 210,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(35),
                              bottomRight: Radius.circular(35),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(35),
                              bottomRight: Radius.circular(35),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // SCHOOL BUILDING BACKGROUND
                                Image.asset(
                                  'assets/aces_building.png',
                                  fit: BoxFit.cover,
                                ),

                                // SUBTLE DARK NAVY OVERLAY
                                Container(color: const Color(0x550B2340)),

                                // CENTER TITLE
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0x990B2340),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.25),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Campus Portal',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 23,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 7),

                                        // GOLD ACCENT
                                        Container(
                                          height: 3,
                                          width: 55,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF2C14E),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // TOP NOTIFICATION ICON
                                SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: Icon(
                                        Icons.notifications,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // WELCOME BACK GREETING
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .snapshots(),
                          builder: (context, snapshot) {
                            final userData = snapshot.data?.data();

                            final firstName =
                                userData?['firstName']
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ==
                                    true
                                ? userData!['firstName'].toString().trim()
                                : (userData?['name']
                                          ?.toString()
                                          .split(' ')
                                          .first ??
                                      'Campus User');

                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'WELCOME TO ACES TAGUM COLLEGE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: Color(0xFFB58A27),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Welcome Back, $firstName!',
                                    style: const TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF123B68),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Ready to explore your campus today?',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // FUNCTIONAL DASHBOARD SEARCH
                        _buildDashboardSearch(context),

                        // EXPLORE CAMPUS
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Explore Campus',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // CAMPUS FEATURES

                        // CAMPUS FEATURES
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .snapshots(),
                          builder: (context, userSnapshot) {
                            if (!userSnapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final role = userSnapshot.data?.data()?['role'];
                            final isAdmin = role == 'admin';

                            return GridView.count(
                              crossAxisCount: 4,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(4),
                              crossAxisSpacing: 9,
                              mainAxisSpacing: 9,
                              childAspectRatio: 0.85,
                              children: [
                                _featureCard(
                                  Icons.calendar_month,
                                  'Schedule',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const SchedulePage(),
                                      ),
                                    );
                                  },
                                ),

                                _featureCard(
                                  Icons.event,
                                  'Events',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const EventsPage(),
                                      ),
                                    );
                                  },
                                ),

                                _featureCard(
                                  Icons.campaign,
                                  'Announcements',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const AnnouncementsPage(),
                                      ),
                                    );
                                  },
                                ),

                                _featureCard(
                                  Icons.groups,
                                  'Clubs',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const ClubsPage(),
                                      ),
                                    );
                                  },
                                ),

                                _featureCard(
                                  Icons.meeting_room,
                                  'Rooms',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const RoomsPage(),
                                      ),
                                    );
                                  },
                                ),

                                // ADMIN ONLY
                                if (isAdmin) ...[
                                  _featureCard(
                                    Icons.school,
                                    'Class Management',
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ClassManagementPage(),
                                        ),
                                      );
                                    },
                                  ),

                                  _featureCard(
                                    Icons.event_available,
                                    'Club Activity Requests',
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ClubActivityApprovalPage(),
                                        ),
                                      );
                                    },
                                  ),

                                  _featureCard(
                                    Icons.manage_accounts,
                                    'User Management',
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const UserManagementPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                _featureCard(
                                  Icons.person,
                                  'Profile',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ProfilePage(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),

                        // CAMPUS UPDATES
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Campus Updates',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        const DashboardAnnouncements(),

                        const SizedBox(height: 20),

                        // CAMPUS CALENDAR
                        const Text(
                          'Campus Calendar',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF245A91),
                          ),
                        ),

                        const SizedBox(height: 12),

                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('events')
                              .orderBy('date')
                              .snapshots(),
                          builder: (context, snapshot) {
                            final eventMap =
                                <DateTime, List<Map<String, dynamic>>>{};

                            if (snapshot.hasData) {
                              for (final doc in snapshot.data!.docs) {
                                final data = doc.data();

                                if (data['status'] == 'archived') continue;
                                if (data['date'] is! Timestamp) continue;

                                final date = _dateOnly(
                                  (data['date'] as Timestamp).toDate(),
                                );

                                eventMap.putIfAbsent(date, () => []);

                                eventMap[date]!.add({
                                  'type': 'event',
                                  'title': data['title'] ?? 'Campus Event',
                                });
                              }
                            }

                            return ValueListenableBuilder<
                              Map<DateTime, List<Map<String, dynamic>>>
                            >(
                              valueListenable: _holidaysByDate,
                              builder: (context, holidayMap, child) {
                                return ValueListenableBuilder<DateTime>(
                                  valueListenable: _selectedDate,
                                  builder: (context, selectedDate, child) {
                                    final selectedEntries = [
                                      ...(eventMap[_dateOnly(selectedDate)] ??
                                          []),
                                      ...(holidayMap[_dateOnly(selectedDate)] ??
                                          []),
                                    ];

                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFFDCE8F4),
                                          width: 1,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x10000000),
                                            blurRadius: 8,
                                            offset: Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          TableCalendar<Map<String, dynamic>>(
                                            firstDay: DateTime(2020),
                                            lastDay: DateTime(2035),
                                            focusedDay: _focusedDate,
                                            selectedDayPredicate: (day) =>
                                                isSameDay(day, selectedDate),
                                            eventLoader: (day) {
                                              final key = _dateOnly(day);

                                              return [
                                                ...(eventMap[key] ?? []),
                                                ...(holidayMap[key] ?? []),
                                              ];
                                            },
                                            onDaySelected: (selected, focused) {
                                              _selectedDate.value = selected;
                                              setState(() {
                                                _focusedDate = focused;
                                              });
                                            },
                                            onPageChanged: (focused) {
                                              _focusedDate = focused;

                                              if (_loadedHolidayYear !=
                                                  focused.year) {
                                                _loadedHolidayYear =
                                                    focused.year;
                                                _loadHolidays(focused.year);
                                              }
                                            },
                                            calendarStyle: const CalendarStyle(
                                              selectedDecoration: BoxDecoration(
                                                color: Color(0xFF245A91),
                                                shape: BoxShape.circle,
                                              ),
                                              todayDecoration: BoxDecoration(
                                                color: Colors.black26,
                                                shape: BoxShape.circle,
                                              ),
                                              markersMaxCount: 2,
                                              outsideDaysVisible: false,
                                            ),
                                            headerStyle: const HeaderStyle(
                                              formatButtonVisible: false,
                                              titleCentered: true,
                                            ),
                                            calendarBuilders: CalendarBuilders<Map<String, dynamic>>(
                                              markerBuilder: (context, day, entries) {
                                                if (entries.isEmpty)
                                                  return null;

                                                final hasEvent = entries.any(
                                                  (item) =>
                                                      item['type'] == 'event',
                                                );

                                                final hasHoliday = entries.any(
                                                  (item) =>
                                                      item['type'] == 'holiday',
                                                );

                                                return Positioned(
                                                  bottom: 4,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (hasEvent)
                                                        Container(
                                                          width: 7,
                                                          height: 7,
                                                          margin:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 1,
                                                              ),
                                                          decoration:
                                                              const BoxDecoration(
                                                                color: Color(
                                                                  0xFF2878D0,
                                                                ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                        ),
                                                      if (hasHoliday)
                                                        Container(
                                                          width: 7,
                                                          height: 7,
                                                          margin:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 1,
                                                              ),
                                                          decoration:
                                                              const BoxDecoration(
                                                                color: Color(
                                                                  0xFF269B59,
                                                                ),
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ),

                                          const SizedBox(height: 12),

                                          const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.circle,
                                                size: 10,
                                                color: Color(0xFF2878D0),
                                              ),
                                              SizedBox(width: 5),
                                              Text(
                                                'Events',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              SizedBox(width: 18),
                                              Icon(
                                                Icons.circle,
                                                size: 10,
                                                color: Color(0xFF269B59),
                                              ),
                                              SizedBox(width: 5),
                                              Text(
                                                'Holidays',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ],
                                          ),

                                          const Divider(height: 24),

                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Activities on ${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: Color(0xFF245A91),
                                              ),
                                            ),
                                          ),

                                          const SizedBox(height: 8),

                                          if (selectedEntries.isEmpty)
                                            const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Text(
                                                'No events or holidays on this date.',
                                              ),
                                            )
                                          else
                                            ...selectedEntries.map((entry) {
                                              final isHoliday =
                                                  entry['type'] == 'holiday';

                                              final color = isHoliday
                                                  ? const Color(0xFF269B59)
                                                  : const Color(0xFF2878D0);

                                              return ListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                leading: Icon(
                                                  isHoliday
                                                      ? Icons.celebration
                                                      : Icons.event,
                                                  color: color,
                                                ),
                                                title: Text(
                                                  entry['title'].toString(),
                                                ),
                                                subtitle: Text(
                                                  isHoliday
                                                      ? 'Philippine Holiday'
                                                      : 'Campus Event',
                                                ),
                                              );
                                            }),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),

                const SchedulePage(),
                const EventsPage(),
                const ProfilePage(),
              ],
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedIndex,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: const Color(0xFF245A91),
              unselectedItemColor: Colors.grey,
              onTap: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Schedule',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.event_outlined),
                  label: 'Events',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _featureCard(IconData icon, String title, {VoidCallback? onTap}) {
    return Material(
      color: const Color(0xFFEAF2FA),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDCE8F4), width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 25, color: const Color(0xFF245A91)),
              ),
              const SizedBox(height: 9),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _selectedDate.dispose();
    _holidaysByDate.dispose();
    _holidaysLoading.dispose();
    super.dispose();
  }
}

// DASHBOARD ANNOUNCEMENTS CAROUSEL

class DashboardAnnouncements extends StatefulWidget {
  const DashboardAnnouncements({super.key});

  @override
  State<DashboardAnnouncements> createState() => _DashboardAnnouncementsState();
}

class _DashboardAnnouncementsState extends State<DashboardAnnouncements> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _announcementsStream;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream;

  final PageController _pageController = PageController();

  Timer? _autoSlideTimer;

  int _currentPage = 0;

  // ACES Tagum College coordinates
  static const double campusLatitude = 7.45775;
  static const double campusLongitude = 125.7922;

  late Future<Map<String, dynamic>> _weatherFuture;

  @override
  void initState() {
    super.initState();

    _announcementsStream = FirebaseFirestore.instance
        .collection('announcements')
        .where('status', isEqualTo: 'published')
        .orderBy('publishedAt', descending: true)
        .snapshots();

    _eventsStream = FirebaseFirestore.instance
        .collection('events')
        .orderBy('date')
        .snapshots();

    _weatherFuture = fetchWeather();

    _startAutoSlide();
  }

  // AUTOMATIC SLIDING

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();

    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_pageController.hasClients) return;

      final nextPage = (_currentPage + 1) % 3;

      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pauseAutoSlide();
    }

    if (notification is ScrollEndNotification) {
      if (_autoSlideTimer == null) {
        _startAutoSlide();
      }
    }

    return false;
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  // WEATHER API

  Future<Map<String, dynamic>> fetchWeather() async {
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$campusLatitude'
      '&longitude=$campusLongitude'
      '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m'
      '&timezone=Asia%2FManila',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Unable to retrieve weather data.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String weatherDescription(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Rain showers';
    if (code <= 86) return 'Snow showers';
    if (code <= 99) return 'Thunderstorm';

    return 'Weather unavailable';
  }

  IconData weatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code <= 3) return Icons.cloud;
    if (code <= 48) return Icons.foggy;
    if (code <= 67) return Icons.water_drop;
    if (code <= 82) return Icons.grain;
    if (code <= 99) return Icons.thunderstorm;

    return Icons.cloud;
  }

  // COMMON CARD DESIGN

  Widget _buildCard({required Widget child}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  // CARD 1: ANNOUNCEMENTS

  Widget _buildAnnouncementCard(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return _buildCard(
        child: const Center(child: Text('Unable to load announcements.')),
      );
    }

    if (!snapshot.hasData) {
      return _buildCard(
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final announcements = snapshot.data!.docs.toList();

    announcements.sort((a, b) {
      final aData = a.data();
      final bData = b.data();

      final aPinned = aData['pinned'] == true;
      final bPinned = bData['pinned'] == true;

      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }

      final aDate = aData['publishedAt'];
      final bDate = bData['publishedAt'];

      final aPublished = aDate is Timestamp
          ? aDate.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);

      final bPublished = bDate is Timestamp
          ? bDate.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);

      return bPublished.compareTo(aPublished);
    });

    if (announcements.isEmpty) {
      return _buildCard(
        child: const Center(child: Text('No announcements available.')),
      );
    }

    final data = announcements.first.data();
    final isPinned = data['pinned'] == true;

    return _buildCard(
      child: Row(
        children: [
          const Icon(Icons.campaign, size: 38, color: Color(0xFF245A91)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ANNOUNCEMENT',
                        style: TextStyle(
                          color: Color(0xFF245A91),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isPinned)
                      const Icon(
                        Icons.push_pin,
                        size: 17,
                        color: Colors.orange,
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  data['title'] ?? 'Untitled Announcement',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  data['description'] ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // CARD 2: EARLIEST UPCOMING EVENT

  Widget _buildEventCard(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return _buildCard(
        child: const Center(child: Text('Unable to load campus events.')),
      );
    }

    if (!snapshot.hasData) {
      return _buildCard(
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final now = DateTime.now();

    final upcomingEvents = snapshot.data!.docs.where((event) {
      final data = event.data();

      if (data['status'] == 'archived') return false;

      final dateValue = data['date'];
      final startTime = data['startTimeMinutes'];

      if (dateValue is! Timestamp || startTime is! int) {
        return false;
      }

      final eventDate = dateValue.toDate();

      final eventStart = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
      ).add(Duration(minutes: startTime));

      return eventStart.isAfter(now);
    }).toList();

    upcomingEvents.sort((a, b) {
      final aData = a.data();
      final bData = b.data();

      final aDate = (aData['date'] as Timestamp).toDate();
      final bDate = (bData['date'] as Timestamp).toDate();

      final aStart = aData['startTimeMinutes'] as int;
      final bStart = bData['startTimeMinutes'] as int;

      final aDateTime = DateTime(
        aDate.year,
        aDate.month,
        aDate.day,
      ).add(Duration(minutes: aStart));

      final bDateTime = DateTime(
        bDate.year,
        bDate.month,
        bDate.day,
      ).add(Duration(minutes: bStart));

      return aDateTime.compareTo(bDateTime);
    });

    if (upcomingEvents.isEmpty) {
      return _buildCard(
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'UPCOMING EVENT',
              style: TextStyle(
                color: Color(0xFF245A91),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            Text('No upcoming events yet.'),
          ],
        ),
      );
    }

    final data = upcomingEvents.first.data();
    final date = (data['date'] as Timestamp).toDate();
    final startMinutes = data['startTimeMinutes'] as int;

    final startTime = TimeOfDay(
      hour: startMinutes ~/ 60,
      minute: startMinutes % 60,
    );

    final formattedDate = '${date.month}/${date.day}/${date.year}';

    return _buildCard(
      child: Row(
        children: [
          const Icon(Icons.event, size: 38, color: Color(0xFF245A91)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UPCOMING EVENT',
                  style: TextStyle(
                    color: Color(0xFF245A91),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  data['title'] ?? 'Untitled Event',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text('$formattedDate \u2022 ${startTime.format(context)}'),
                Text(
                  data['location'] ?? 'Location not specified',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // CARD 3: CAMPUS WEATHER

  Widget _buildWeatherCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _weatherFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildCard(
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildCard(
            child: Row(
              children: [
                const Icon(Icons.cloud_off, size: 38),
                const SizedBox(width: 14),
                const Expanded(child: Text('Weather information unavailable.')),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _weatherFuture = fetchWeather();
                    });
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          );
        }

        final current = snapshot.data!['current'];

        final temperature = current['temperature_2m'];
        final feelsLike = current['apparent_temperature'];
        final humidity = current['relative_humidity_2m'];
        final wind = current['wind_speed_10m'];
        final code = current['weather_code'] as int;

        return _buildCard(
          child: Row(
            children: [
              Icon(weatherIcon(code), size: 44, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'CAMPUS WEATHER',
                      style: TextStyle(
                        color: Color(0xFF245A91),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${temperature.round()}\u00B0C',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(weatherDescription(code)),
                    const SizedBox(height: 2),
                    Text(
                      'Feels like ${feelsLike.round()}\u00B0C \u2022 Humidity $humidity%',
                      style: const TextStyle(fontSize: 10),
                    ),
                    Text(
                      'Wind: $wind km/h',
                      style: const TextStyle(fontSize: 10),
                    ),
                    const Text(
                      'ACES Tagum College',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh weather',
                onPressed: () {
                  setState(() {
                    _weatherFuture = fetchWeather();
                  });
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 175,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _announcementsStream,
                  builder: (context, snapshot) {
                    return _buildAnnouncementCard(snapshot);
                  },
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _eventsStream,
                  builder: (context, snapshot) {
                    return _buildEventCard(snapshot);
                  },
                ),
                _buildWeatherCard(),
              ],
            ),
          ),
        ),

        // PREVIOUS / NEXT BUTTONS AND PAGE INDICATORS
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous',
              onPressed: () {
                _goToPage((_currentPage - 1 + 3) % 3);
              },
              icon: const Icon(Icons.arrow_back_ios),
            ),
            Row(
              children: List.generate(3, (index) {
                final isSelected = _currentPage == index;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isSelected ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF245A91)
                        : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              }),
            ),
            IconButton(
              tooltip: 'Next',
              onPressed: () {
                _goToPage((_currentPage + 1) % 3);
              },
              icon: const Icon(Icons.arrow_forward_ios),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }
}
