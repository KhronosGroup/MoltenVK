import argparse

def getArguments():
    parser = argparse.ArgumentParser(description="Retrieve failing tests from CTS output file")
    parser.add_argument("inputFile", help="Input file")
    parser.add_argument("-o", "--output", dest="outputFile", default="failingTests.txt", type=str, required=False, help="Output file to store failing tests")
    parser.add_argument('-q', action='store_true')
    return parser.parse_args()

if __name__ == "__main__":
    args = getArguments()

    with open(args.inputFile, "r") as inputFile:
        with open(args.outputFile, "w") as outputFile:
            if not args.q:
                print("Reading file " + args.inputFile + " for test failures")

            testName = ""
            for line in inputFile:
                # Empty lines means we have changed test
                if line == "\n":
                    testName = ""
                    continue

                # Assuming lines with test names are formatted like: "Test case 'dEQP-VK.test.name'.."
                if "Test case" in line:
                    testName = line[11:-4]
                    continue

                # Failed tests will have a line after the test that should be like: "Fail (sometimes the reason here)"
                if testName != "" and "Fail" in line:
                    outputFile.writelines(testName + "\n")

            if not args.q:
                print("Failures written to " + args.outputFile)
    pass
