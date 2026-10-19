# Keep parameterless constructors on RoomDatabase implementations (e.g. WorkDatabase_Impl)
# which are instantiated reflectively by Room in WorkManager.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
