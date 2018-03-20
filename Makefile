.PHONY : build clean

all: | build

clean:
	@rm -rf build

build:
	@mkdir -p build
	@cd build && cmake .. && make
