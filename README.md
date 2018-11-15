# Basic Three-Tier AWS Architecture

This provides a template for running a simple two-tier architecture on Amazon
Web services. The premise is that you have stateless app servers running behind
an ELB serving traffic. A seperate RDS db tier is also created.

To simplify the example, this intentionally ignores deploying and
getting your application onto the servers. However, you could do so either via
[provisioners](https://www.terraform.io/docs/provisioners/) and a configuration
management tool, or by pre-baking configured AMIs with
[Packer](http://www.packer.io).

This example will also create a new EC2 Key Pair in the specified AWS Region. 
The key name and path to the public key must be specified via the  
terraform command vars or in the variables.tf file.

After you run `terraform apply` on this configuration, it will
automatically output the DNS address of the ELB. After your instance
registers, this should respond with the default nginx web page.

The system reads your AWS credentials from a running instance of vault