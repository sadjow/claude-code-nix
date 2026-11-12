import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPRESSION = re.compile(r'\$\{\{\s*(.*?)\s*\}\}')


class ReleaseWorkflowsTest(unittest.TestCase):
    def test_tags_use_the_commit_that_passed_the_build(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/create-version-tag.yml').read_text())
        checkout = next(step for step in workflow['jobs']['create-tag']['steps']
                        if step.get('uses', '').startswith('actions/checkout@'))
        self.assertEqual(checkout['with'].get('ref'), '${{ github.event.workflow_run.head_sha }}',
                         'A newer default-branch commit must not be tagged using an older build result')

    def test_tags_only_trusted_default_branch_builds(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/create-version-tag.yml').read_text())
        condition = workflow['jobs']['create-tag']['if']
        self.assertIn("github.event.workflow_run.event != 'pull_request'", condition,
                      'A fork pull request from a branch named main must not reach the tagging job')
        self.assertIn('github.event.workflow_run.head_repository.full_name == github.repository', condition,
                      'Only builds of this repository may move the release tags')


class CreateVersionTagStepsTest(unittest.TestCase):
    def setUp(self):
        workdir = tempfile.TemporaryDirectory()
        self.addCleanup(workdir.cleanup)
        self.workdir = pathlib.Path(workdir.name)
        self.env = {
            **os.environ,
            'GIT_CONFIG_GLOBAL': os.devnull,
            'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_AUTHOR_NAME': 'Release Test',
            'GIT_AUTHOR_EMAIL': 'release-test@example.com',
            'GIT_COMMITTER_NAME': 'Release Test',
            'GIT_COMMITTER_EMAIL': 'release-test@example.com',
        }
        self.origin = self.workdir / 'origin.git'
        self.maintainer = self.workdir / 'maintainer'
        self.release_2_1_0, self.release_2_2_0 = self.publish_releases()

    def git(self, cwd, *args):
        result = subprocess.run(['git', *args], cwd=cwd, env=self.env, capture_output=True, text=True)
        if result.returncode != 0:
            self.fail(f'git {" ".join(args)} failed: {result.stderr.strip()}')
        return result.stdout.strip()

    def commit_release(self, version):
        (self.maintainer / 'package.nix').write_text(f'version = "{version}";\n')
        self.git(self.maintainer, 'add', '-A')
        self.git(self.maintainer, 'commit', '-qm', f'Release {version}')
        return self.git(self.maintainer, 'rev-parse', 'HEAD')

    def publish_releases(self):
        self.git(self.workdir, 'init', '-q', '--bare', '-b', 'main', str(self.origin))
        self.git(self.workdir, 'clone', '-q', str(self.origin), str(self.maintainer))
        # Releases made before the helper existed have commits without it.
        release_2_1_0 = self.commit_release('2.1.0')
        (self.maintainer / 'scripts').mkdir()
        shutil.copy(ROOT / 'scripts/update-moving-tags.sh', self.maintainer / 'scripts')
        release_2_2_0 = self.commit_release('2.2.0')
        self.git(self.maintainer, 'push', '-q', 'origin', 'main')
        self.publish_tags(release_2_1_0, 'v2.1.0')
        return release_2_1_0, release_2_2_0

    def publish_tags(self, commit, *tags):
        for tag in tags:
            self.git(self.maintainer, 'tag', '-f', '-a', tag, '-m', tag, commit)
            self.git(self.maintainer, 'push', '-q', '--force', 'origin', f'refs/tags/{tag}')

    def published_commit(self, tag):
        return self.git(self.origin, 'rev-parse', f'{tag}^{{commit}}')

    def run_tag_steps(self, commit, version, tag_exists, step_names):
        workflow = yaml.safe_load((ROOT / '.github/workflows/create-version-tag.yml').read_text())
        steps = {step.get('name'): step for step in workflow['jobs']['create-tag']['steps']}
        expressions = {
            'steps.version.outputs.version': version,
            'steps.check-tag.outputs.exists': tag_exists,
            'steps.major.outputs.major': version.split('.')[0],
            'github.workflow_sha': self.release_2_2_0,
        }

        def resolve(text):
            return EXPRESSION.sub(lambda match: expressions[match.group(1)], str(text))

        runner = self.workdir / 'runner'
        runner_temp = self.workdir / 'runner-temp'
        summary = self.workdir / 'summary.md'
        runner_temp.mkdir()
        self.git(self.workdir, 'clone', '-q', str(self.origin), str(runner))
        self.git(runner, 'checkout', '-q', '--detach', commit)
        for name in step_names:
            step = steps[name]
            env = {
                **self.env,
                'RUNNER_TEMP': str(runner_temp),
                'GITHUB_STEP_SUMMARY': str(summary),
                **{key: resolve(value) for key, value in step.get('env', {}).items()},
            }
            result = subprocess.run(['bash', '--noprofile', '--norc', '-eo', 'pipefail', '-c', resolve(step['run'])],
                                    cwd=runner, env=env, capture_output=True, text=True)
            if result.returncode != 0:
                self.fail(f'"{name}" exited with status {result.returncode}: {result.stderr.strip()}')
        return summary.read_text()

    def test_rerun_of_build_without_helper_keeps_newer_release(self):
        self.publish_tags(self.release_2_2_0, 'v2.2.0', 'latest', 'v2')

        summary = self.run_tag_steps(self.release_2_1_0, '2.1.0', 'true',
                                     ['Configure git', 'Update moving tags', 'Summary'])

        for tag in ('latest', 'v2'):
            self.assertEqual(self.published_commit(tag), self.release_2_2_0,
                             f'A rerun of the 2.1.0 build must not move {tag} back')
            self.assertIn(f'| {tag} | {self.release_2_2_0[:7]} (newer release, unchanged) |', summary)

    def test_release_moves_both_tags_and_reports_them(self):
        self.publish_tags(self.release_2_1_0, 'latest', 'v2')

        summary = self.run_tag_steps(self.release_2_2_0, '2.2.0', 'false',
                                     ['Configure git', 'Create and push version tag', 'Update moving tags', 'Summary'])

        for tag in ('v2.2.0', 'latest', 'v2'):
            self.assertEqual(self.published_commit(tag), self.release_2_2_0)
        for tag in ('latest', 'v2'):
            self.assertIn(f'| {tag} | v2.2.0 |', summary)


if __name__ == '__main__':
    unittest.main()
