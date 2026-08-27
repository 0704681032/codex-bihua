/// Callback invoked when the user navigates browser history
/// (back/forward). [char] is the detail char encoded in the resulting
/// URL, or null when the URL points at the home page.
typedef HistoryListener = void Function(String? char);

String? readCharFromUrl() => null;

void setHistoryListener(HistoryListener? listener) {}

void syncDetailUrl(String char) {}

void syncHomeUrl() {}

void configureEngineUrlStrategy() {}
