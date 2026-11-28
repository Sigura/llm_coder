kotlinc solution.kt TestKit.kt Test.kt -include-runtime -nowarn -d t.jar 2>&1
[[ -f t.jar ]] || { echo "0/1 passed (compile error)"; exit 1; }
java -jar t.jar
