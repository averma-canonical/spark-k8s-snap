from random import random

from pyspark.context import SparkContext
from pyspark.sql.session import SparkSession


sc = SparkContext()
spark = SparkSession(sc)
text_file = spark.read.text("EXAMPLE_TEXT_FILE")
print(f"Number of lines {text_file.count()}")