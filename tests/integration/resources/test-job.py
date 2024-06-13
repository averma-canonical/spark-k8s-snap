import argparse
from pyspark.sql import SparkSession

def main(file_path):
    # Initialize a Spark session
    spark = SparkSession.builder \
        .appName("Simple Integration Test Job") \
        .getOrCreate()

    # Read the text file
    text_file = spark.read.text(file_path)

    # Count the number of lines in the text file
    line_count = text_file.count()

    print(f"Number of lines {line_count}")

    # Stop the Spark session
    spark.stop()

if __name__ == "__main__":
    # Set up argument parsing
    parser = argparse.ArgumentParser(description='Simple Spark Job for Integration Testing')
    parser.add_argument('file_path', type=str, help='Path to the text file')

    # Parse the arguments
    args = parser.parse_args()

    # Call the main function with the provided file path
    main(args.file_path)
