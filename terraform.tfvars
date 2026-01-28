region = "us-ashburn-1"
region_identifier = "IAD"
kubernetes_version = "v1.34.1"
# Find the lastest image from here that uses that kubernetes version you chose and that is aarch64 and click on it
# https://docs.oracle.com/en-us/iaas/images/oke-worker-node-oracle-linux-8x/index.htm
# Grab the ocid for that image from that page, and add image_id = "<image ocid>"
image_id = "ocid1.image.oc1.iad.aaaaaaaawmemtmpxmbtbnqbn6vdr5s7u22cf5ctencd46w2u65p4syungxmq"