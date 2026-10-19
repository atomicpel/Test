package ru.atomicpel.cycle_app

import androidx.core.content.FileProvider

/** Свой класс, чтобы не пересекаться с FileProvider из плагинов. */
class ApkFileProvider : FileProvider()
