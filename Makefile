.PHONY : build clean

all: | build

clean:
	@rm -rf build ${shell find External -mindepth 1 -maxdepth 1 -type d -print}

build:
	@mkdir -p build
	@cd build && cmake .. && make
