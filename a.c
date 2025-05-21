#include <stdio.h>
#include <stdlib.h>

#define BUFFER_SIZE 4096

int main() {
    FILE *inputFile, *outputFile;
    char inputFileName[100], outputFileName[100];
    char buffer[BUFFER_SIZE];
    size_t bytesRead;
    fprintf(stderr, "BLA\n");
    setenv("_BPXK_PCCSID", "1208", 1);
    fprintf(stderr, "BLA\n");

    // Get input file name
    printf("Enter the name of the input file: ");
    scanf("%s", inputFileName);

    // Open the input file for reading
    inputFile = fopen(inputFileName, "rb");
    if (inputFile == NULL) {
        perror("Error opening input file");
        exit(EXIT_FAILURE);
    }

    // Print the contents of the input file to the console
    printf("Contents of the input file:\n");
    while ((bytesRead = fread(buffer, 1, BUFFER_SIZE, inputFile)) > 0) {
        fwrite(buffer, 1, bytesRead, stdout);
    }

    // Close the input file
    fclose(inputFile);

    // Get output file name
    printf("\nEnter the name of the output file: ");
    scanf("%s", outputFileName);

    // Open the output file for writing
    outputFile = fopen(outputFileName, "wb");
    if (outputFile == NULL) {
        perror("Error opening output file");
        exit(EXIT_FAILURE);
    }

    // Reopen the input file for reading
    inputFile = fopen(inputFileName, "rb");
    if (inputFile == NULL) {
        perror("Error reopening input file");
        fclose(outputFile);
        exit(EXIT_FAILURE);
    }

    // Read from the input file and write to the output file
    while ((bytesRead = fread(buffer, 1, BUFFER_SIZE, inputFile)) > 0) {
        fwrite(buffer, 1, bytesRead, outputFile);
    }

    // Close the files
    fclose(inputFile);
    fclose(outputFile);

    printf("\nFile copied successfully.\n");

    return 0;
}

