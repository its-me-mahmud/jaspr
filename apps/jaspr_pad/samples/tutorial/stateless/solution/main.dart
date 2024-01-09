// [sample][hidden] Tutorial
import 'package:jaspr/jaspr.dart';

void main() {
  runApp(App());
}

class App extends StatelessComponent {
  const App({Key? key}) : super(key: key);

  @override
  Iterable<Component> build(BuildContext context) sync* {
    yield div([
      h1([text('Hello World!')]),
      p([text('You\'re great!')]),
    ]);
  }
}
