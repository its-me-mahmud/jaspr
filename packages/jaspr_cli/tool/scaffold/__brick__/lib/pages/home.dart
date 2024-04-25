import 'package:jaspr/jaspr.dart';

import '../components/counter.dart';
{{#hydration}}{{#multipage}}
@client{{/multipage}}{{/hydration}}
class Home extends StatelessComponent {
  const Home({super.key});

  @override
  Iterable<Component> build(BuildContext context) sync* {
    yield section([
      img(src: 'images/logo.png', width: 80),
      h1([text('Welcome')]),
      p([text('You successfully create a new Jaspr site.')]),
      div(styles: Styles.box(height: 100.px), []),
      const Counter(),
    ]);
  }{{#server}}

  static get styles => [
        ...Counter.styles,
      ];{{/server}}
}
