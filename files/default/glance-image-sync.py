#!/usr/bin/env python
#
# Copyright 2012, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

import glob
import os
import socket
import sys
import ConfigParser
from kombu import BrokerConnection
from kombu import Exchange
from kombu import Queue

IMAGE_SYNC_CONFIG = '/etc/glance/glance-image-sync.conf'
GLANCE_API_CONFIG = '/etc/glance/glance-api.conf'


def _read_api_nodes_config():
    config = ConfigParser.RawConfigParser()
    section = 'DEFAULT'

    if config.read(IMAGE_SYNC_CONFIG):
        return config.get(section, 'api_nodes').replace(' ', '').split(',')
    else:
        return None


def _read_glance_api_config():
    glance_cfg = {}
    section = 'DEFAULT'
    config = ConfigParser.RawConfigParser()

    if config.read(GLANCE_API_CONFIG):
        if config.get(section, 'notifier_strategy') == 'rabbit':
            glance_cfg['host'] = config.get(section, 'rabbit_host')
            glance_cfg['port'] = config.get(section, 'rabbit_port')
            glance_cfg['use_ssl'] = config.get(section, 'rabbit_use_ssl')
            glance_cfg['userid'] = config.get(section, 'rabbit_userid')
            glance_cfg['password'] = config.get(section,
                                                'rabbit_password')
            glance_cfg['virtual_host'] = config.get(section,
                                                    'rabbit_virtual_host')
            glance_cfg['exchange'] = config.get(section,
                                                'rabbit_notification_exchange')
            glance_cfg['topic'] = config.get(section,
                                             'rabbit_notification_topic')
            glance_cfg['datadir'] = config.get(section,
                                               'filesystem_store_datadir')

            return glance_cfg
        else:
            return None
    else:
        return None


def _connect(glance_cfg):
    # We use BrokerConnection rather than Connection as RHEL 6 has an ancient
    # version of kombu library.
    conn = BrokerConnection(hostname=glance_cfg['host'],
                            port=glance_cfg['port'],
                            userid=glance_cfg['userid'],
                            password=glance_cfg['password'],
                            virtual_host=glance_cfg['virtual_host'])
    exchange = Exchange(glance_cfg['exchange'],
                        type='topic',
                        durable=False,
                        channel=conn.channel())

    return conn, exchange


def _declare_queue(glance_cfg, routing_key, conn, exchange):
    queue = Queue(name=routing_key,
                  routing_key=routing_key,
                  exchange=exchange,
                  channel=conn.channel(),
                  durable=False)
    queue.declare()

    return queue


def _shorten_hostname(node):
    # If hostname is an FQDN, split it up and return the short name. Some
    # systems may return FQDN on socket.gethostname(), so we choose one
    # and run w/ that.
    if '.' in node:
        return node.split('.')[0]
    else:
        return node 


def _duplicate_notifications(glance_cfg, api_nodes, conn, exchange):
    routing_key = '%s.info' % glance_cfg['topic']
    notification_queue = _declare_queue(glance_cfg,
                                        routing_key,
                                        conn,
                                        exchange)

    while True:
        msg = notification_queue.get()

        if msg is None:
            break

        for node in api_nodes:
            routing_key = 'glance_image_sync.%s.info' % _shorten_hostname(node)
            node_queue = _declare_queue(glance_cfg,
                                        routing_key,
                                        conn,
                                        exchange)

            msg_new = exchange.Message(msg.body,
                                       content_type='application/json')
            exchange.publish(msg_new, routing_key)

        msg.ack()


def _sync_images(glance_cfg, conn, exchange):
    hostname = socket.gethostname()

    routing_key = 'glance_image_sync.%s.info' % _shorten_hostname(hostname)
    queue = _declare_queue(glance_cfg, routing_key, conn, exchange)

    while True:
        msg = queue.get()

        if msg is None: break

        image_filename = "%s/%s" % (glance_cfg['datadir'],
                                    msg.payload['payload']['id'])

        # An image create generates a create and update notification, so we
        # just pass over the create notification and use the update one
        # instead.
        # Also, we don't send the update notification to the node which
        # processed the request (publisher_id) since that node will already
        # have the image; we do send deletes to all nodes though since the 
        # node which receives the delete request may not have the completed
        # image yet.
        if (msg.payload['event_type'] == 'image.update' and
            msg.payload['publisher_id'] != hostname):
            print 'Update detected on %s ...' % (image_filename)
            os.system("rsync -a -e 'ssh -o StrictHostKeyChecking=no' "
                      "root@%s:%s %s" % (msg.payload['publisher_id'],
                                         image_filename, image_filename))
            msg.ack()
        elif msg.payload['event_type'] == 'image.delete':
            print 'Delete detected on %s ...' % (image_filename)
            # Don't delete file if it's still being copied (we're looking for
            # the temporary file as it's being copied by rsync here).
            image_glob = '%s/.*%s*' % (glance_cfg['datadir'],
                                       msg.payload['payload']['id'])
            if not glob.glob(image_glob):
                os.system('rm %s' % (image_filename))
                msg.ack()
        else:
            msg.ack()


def main(args):
    if len(args) == 2:
        cmd = args[1]
    else:
        sys.exit(1)

    if cmd in ('duplicate-notifications', 'sync-images', 'both'):
        glance_cfg = _read_glance_api_config()
        api_nodes = _read_api_nodes_config()

        if glance_cfg and api_nodes:
            conn, exchange = _connect(glance_cfg)
        else:
            sys.exit(1)
    else:
        sys.exit(1)

    if cmd == 'duplicate-notifications':
        _duplicate_notifications(glance_cfg, api_nodes, conn, exchange)
    elif cmd == 'sync-images':
        _sync_images(glance_cfg, conn, exchange)
    elif cmd == 'both':
        _duplicate_notifications(glance_cfg, api_nodes, conn, exchange)
        _sync_images(glance_cfg, conn, exchange)

    conn.close()


if __name__ == '__main__':
    main(sys.argv)
