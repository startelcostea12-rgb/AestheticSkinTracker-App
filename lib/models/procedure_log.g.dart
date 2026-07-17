// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'procedure_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProcedureLogAdapter extends TypeAdapter<ProcedureLog> {
  @override
  final int typeId = 5;

  @override
  ProcedureLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProcedureLog(
      id: fields[0] as String?,
      procedureType: fields[1] as String,
      dateTime: fields[2] as DateTime,
      notes: fields[3] as String?,
      photoPaths: (fields[4] as List).cast<String>(),
      intensity: fields[5] as int?,
      settings: fields[6] as String?,
      productsUsed: (fields[7] as List).cast<String>(),
      reactionScore: fields[8] as int?,
      aiFeedback: fields[9] as String?,
      createdAt: fields[10] as DateTime?,
      category: fields[11] as String?,
      expectedDuration: fields[12] as String?,
      nextReminderDate: fields[13] as DateTime?,
      reminderEnabled: fields[14] as bool?,
      photoLabels: (fields[15] as List?)?.cast<String>() ?? const <String>[],
    );
  }

  @override
  void write(BinaryWriter writer, ProcedureLog obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.procedureType)
      ..writeByte(2)
      ..write(obj.dateTime)
      ..writeByte(3)
      ..write(obj.notes)
      ..writeByte(4)
      ..write(obj.photoPaths)
      ..writeByte(5)
      ..write(obj.intensity)
      ..writeByte(6)
      ..write(obj.settings)
      ..writeByte(7)
      ..write(obj.productsUsed)
      ..writeByte(8)
      ..write(obj.reactionScore)
      ..writeByte(9)
      ..write(obj.aiFeedback)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.category)
      ..writeByte(12)
      ..write(obj.expectedDuration)
      ..writeByte(13)
      ..write(obj.nextReminderDate)
      ..writeByte(14)
      ..write(obj.reminderEnabled)
      ..writeByte(15)
      ..write(obj.photoLabels);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProcedureLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
