import 'package:flutter/material.dart';

import '../db/database_helper.dart';

/// Exercise History — lists every saved session, most recent first.
///
/// Task 1 wires the route; Task 2 fills in the list, empty state and detail
/// navigation.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.databaseHelper});

  final DatabaseHelper databaseHelper;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise History')),
      body: const SizedBox.shrink(),
    );
  }
}
