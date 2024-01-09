import 'package:jaspr/jaspr.dart';

class Counter extends StatefulComponent {
  const Counter({Key? key}) : super(key: key);

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;

  void increment() {
    setState(() {
      count++;
    });
  }

  @override
  Iterable<Component> build(BuildContext context) sync* {
    yield text('Count: $count');

    yield button(
      events: {'click': (e) => increment()},
      [text('Counter')],
    );
  }
}
