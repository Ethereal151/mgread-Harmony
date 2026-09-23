part of 'library_home_shell_test.dart';

LibraryHomeViewData _largeLibraryHomeData(int count) => LibraryHomeViewData(
  isPresentationFixture: true,
  continueReading: null,
  books: List<LibraryBookListItemViewData>.generate(
    count,
    (int index) => LibraryBookListItemViewData(
      id: 'performance-book-$index',
      title: '性能测试书 $index',
      coverVariant: LibraryCoverVariant.values[index % LibraryCoverVariant.values.length],
      status: LibraryBookStatus.local,
    ),
  ),
);
