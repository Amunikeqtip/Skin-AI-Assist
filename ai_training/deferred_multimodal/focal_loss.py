"""Per-example focal loss used by the multimodal trainer."""

from __future__ import annotations

import tensorflow as tf


@tf.keras.utils.register_keras_serializable(package="skinai")
class SparseFocalLoss(tf.keras.losses.Loss):
    def __init__(self, gamma: float = 2.0, **kwargs):
        kwargs["reduction"] = tf.keras.losses.Reduction.NONE
        kwargs.setdefault("name", "sparse_focal")
        super().__init__(**kwargs)
        self.gamma = float(gamma)

    def call(self, y_true, y_pred):
        labels = tf.cast(tf.reshape(y_true, [-1]), tf.int32)
        cross_entropy = tf.nn.sparse_softmax_cross_entropy_with_logits(
            labels=labels, logits=y_pred
        )
        probability = tf.exp(-cross_entropy)
        return tf.pow(1.0 - probability, self.gamma) * cross_entropy

    def get_config(self):
        config = super().get_config()
        config.update({"gamma": self.gamma})
        return config
