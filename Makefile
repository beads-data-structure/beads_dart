DARTANALYZER_FLAGS=--fatal-warnings
SOURCES=lib/*dart

build: ${SOURCES} test/*dart deps
	dartanalyzer ${DARTANALYZER_FLAGS} lib/
	dartfmt -n --set-exit-if-changed lib/ test/
	pub run test_coverage

reformatting:
	dartfmt -w lib/ test/

deps: pubspec.yaml
	pub get

reformatting:
	dartfmt -w lib/ test/

build-local: reformatting build
	genhtml -o coverage coverage/lcov.info
	open coverage/index.html

publish:
	pub publish