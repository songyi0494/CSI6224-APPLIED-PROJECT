import 'package:flutter/material.dart';
import '../data/app_repository.dart';

class AsyncPanel<T> extends StatefulWidget {
  const AsyncPanel({required this.load, required this.builder, super.key});
  final Future<T> Function() load;
  final Widget Function(T, VoidCallback) builder;
  @override
  State<AsyncPanel<T>> createState() => _AsyncPanelState<T>();
}

class _AsyncPanelState<T> extends State<AsyncPanel<T>> {
  late Future<T> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _reload() {
    final next = widget.load();
    setState(() {
      _future = next;
    });
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                snapshot.error is AppException
                    ? (snapshot.error as AppException).message
                    : 'We could not load this information. Please try again.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            ],
          ),
        );
      if (!snapshot.hasData)
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      return widget.builder(snapshot.data as T, _reload);
    },
  );
}
