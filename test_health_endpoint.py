import asyncio
import os
import unittest

import main


class HealthEndpointTests(unittest.TestCase):
    """GET /health reports the backend's deployed git commit, baked in as
    the GIT_COMMIT env var at `docker build --build-arg GIT_COMMIT=...`
    time (see the Dockerfile). Missing/unset -> "unknown", never a failure.
    """

    def setUp(self):
        self._original = os.environ.get("GIT_COMMIT")

    def tearDown(self):
        if self._original is None:
            os.environ.pop("GIT_COMMIT", None)
        else:
            os.environ["GIT_COMMIT"] = self._original

    def test_returns_ok_status(self):
        os.environ.pop("GIT_COMMIT", None)
        result = asyncio.run(main.health_check())
        self.assertEqual(result["status"], "ok")

    def test_missing_env_var_reports_unknown_without_failing(self):
        os.environ.pop("GIT_COMMIT", None)
        result = asyncio.run(main.health_check())
        self.assertEqual(result["commit"], "unknown")

    def test_empty_env_var_reports_unknown(self):
        os.environ["GIT_COMMIT"] = "   "
        result = asyncio.run(main.health_check())
        self.assertEqual(result["commit"], "unknown")

    def test_set_env_var_is_echoed_back_exactly(self):
        os.environ["GIT_COMMIT"] = "a1b2c3d4e5f6"
        result = asyncio.run(main.health_check())
        self.assertEqual(result["commit"], "a1b2c3d4e5f6")

    def test_env_var_is_trimmed(self):
        os.environ["GIT_COMMIT"] = "  a1b2c3d4  \n"
        result = asyncio.run(main.health_check())
        self.assertEqual(result["commit"], "a1b2c3d4")


if __name__ == "__main__":
    unittest.main()
