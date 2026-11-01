enum AppTypeface {
  system('系统字体', null);

  const AppTypeface(this.label, this.family);
  final String label;
  final String? family;
  // Older releases stored `sourceHanSerif`. Its font is no longer bundled;
  // keep the stored reading anchors, but resolve that choice to the platform.
  static AppTypeface fromRecord(Object? value) => AppTypeface.system;
}
